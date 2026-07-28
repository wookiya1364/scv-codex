#!/usr/bin/env bash
# Verify Codex's read-only model-policy compatibility contract.
#
# Codex does not support a model override in skill frontmatter. Legacy policy
# names remain accepted so existing SCV projects do not break, but every valid
# policy resolves to the session/default Codex model and changes no files.
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$PLUGIN_ROOT/scripts/apply-model-policy.sh"

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

assert_rc() {
  local label="$1" actual="$2" expected="$3"
  if [[ "$actual" -eq "$expected" ]]; then
    ok "$label: exit $expected"
  else
    fail "$label: expected exit $expected, got $actual"
  fi
}

assert_output() {
  local label="$1" output="$2" expected="$3"
  if grep -qF "$expected" <<<"$output"; then
    ok "$label: contains '$expected'"
  else
    fail "$label: missing '$expected'"
    printf '    output: %s\n' "$output"
  fi
}

fingerprint_runtime_docs() {
  python3 - "$PLUGIN_ROOT" <<'PY'
import hashlib
import sys
from pathlib import Path

root = Path(sys.argv[1])
digest = hashlib.sha256()
for base in (root / "skills", root / "references" / "protocols"):
    for path in sorted(p for p in base.rglob("*") if p.is_file()):
        digest.update(path.relative_to(root).as_posix().encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
print(digest.hexdigest())
PY
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "── apply-model-policy.sh Codex compatibility tests ──"

# Missing/empty legacy configuration resolves to the Codex session default.
for scenario in no-env no-key empty-value; do
  project="$WORK/$scenario"
  mkdir -p "$project"
  case "$scenario" in
    no-key)
      printf 'SOME_OTHER_VAR=1\n' >"$project/.env"
      ;;
    empty-value)
      printf 'SCV_MODEL_POLICY=\n' >"$project/.env"
      ;;
  esac

  output="$(SCV_PROJECT_DIR="$project" bash "$SCRIPT" --from-env 2>&1)"
  rc=$?
  assert_rc "$scenario" "$rc" 0
  assert_output "$scenario" "$output" "POLICY: session-default"
  assert_output "$scenario" "$output" "SUPPORTED: yes"
  assert_output "$scenario" "$output" "EFFECTIVE_POLICY: session-default"
  assert_output "$scenario" "$output" "CHANGED_FILES: 0"
done

# A legacy policy is accepted for compatibility but never mutates skill files.
project="$WORK/legacy-policy"
mkdir -p "$project"
printf 'SCV_MODEL_POLICY=all-opus\n' >"$project/.env"
before="$(fingerprint_runtime_docs)"
output="$(SCV_PROJECT_DIR="$project" bash "$SCRIPT" --from-env 2>&1)"
rc=$?
after="$(fingerprint_runtime_docs)"
assert_rc "legacy all-opus" "$rc" 0
assert_output "legacy all-opus" "$output" "POLICY: all-opus"
assert_output "legacy all-opus" "$output" "SUPPORTED: no"
assert_output "legacy all-opus" "$output" "EFFECTIVE_POLICY: session-default"
assert_output "legacy all-opus" "$output" "CHANGED_FILES: 0"
if [[ "$before" == "$after" ]]; then
  ok "legacy all-opus: skills and protocols remain byte-identical"
else
  fail "legacy all-opus: skills or protocols were modified"
fi

# Direct session-default invocation has the same explicit diagnostic contract.
output="$(bash "$SCRIPT" --policy session-default 2>&1)"
rc=$?
assert_rc "direct session-default" "$rc" 0
assert_output "direct session-default" "$output" "POLICY: session-default"
assert_output "direct session-default" "$output" "SUPPORTED: yes"
assert_output "direct session-default" "$output" "CHANGED_FILES: 0"

# Unknown policies still fail validation.
project="$WORK/invalid-policy"
mkdir -p "$project"
printf 'SCV_MODEL_POLICY=not-a-real-policy\n' >"$project/.env"
output="$(SCV_PROJECT_DIR="$project" bash "$SCRIPT" --from-env 2>&1)"
rc=$?
assert_rc "invalid policy" "$rc" 2
assert_output "invalid policy" "$output" "invalid policy"

echo
echo "── result: $PASS passed, $FAIL failed ──"
[[ "$FAIL" -eq 0 ]]
