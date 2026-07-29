#!/usr/bin/env bash
# Regression checks for Codex state-index compatibility around shared SCV Core.

set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_INDEX="$PLUGIN_ROOT/adapter/scripts/state-index.sh"
SYNC_SHIM="$PLUGIN_ROOT/adapter/scripts/sync.sh"

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
  local file=$1
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    echo "error: sha256sum or shasum is required" >&2
    return 1
  fi
}

assert_file() {
  local path="$1" label="$2"
  if [[ -f "$path" ]]; then
    ok "$label"
  else
    fail "$label (missing: $path)"
  fi
}

assert_absent() {
  local path="$1" label="$2"
  if [[ ! -e "$path" ]]; then
    ok "$label"
  else
    fail "$label (unexpected: $path)"
  fi
}

assert_contains() {
  local text="$1" expected="$2" label="$3"
  if grep -qF "$expected" <<<"$text"; then
    ok "$label"
  else
    fail "$label (missing '$expected')"
  fi
}

assert_rc() {
  local actual="$1" expected="$2" label="$3"
  if [[ "$actual" -eq "$expected" ]]; then
    ok "$label"
  else
    fail "$label (expected $expected, got $actual)"
  fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "── shared-core state adapter ──"

# A Claude-only project is already hydrated. Inspection must be byte-for-byte
# read-only and must not manufacture either canonical or Codex state.
claude_project="$WORK/claude-only"
mkdir -p "$claude_project/scv"
printf '# existing Claude state\n\nPROJECT: LOCAL\nSTATUS: N/A\n' \
  >"$claude_project/scv/CLAUDE.md"
before="$(portable_sha256 "$claude_project/scv/CLAUDE.md")"
output="$(bash "$STATE_INDEX" --project-dir "$claude_project" 2>&1)"
rc=$?
after="$(portable_sha256 "$claude_project/scv/CLAUDE.md")"
assert_rc "$rc" 0 "CLAUDE.md-only inspection succeeds"
assert_contains "$output" "STATE_INDEX: legacy" \
  "CLAUDE.md-only project is recognized as hydrated"
assert_contains "$output" "HYDRATED: yes" \
  "legacy state reports hydrated explicitly"
if [[ "$before" == "$after" ]]; then
  ok "CLAUDE.md-only inspection preserves the legacy file"
else
  fail "CLAUDE.md-only inspection changed the legacy file"
fi
assert_absent "$claude_project/scv/SCV.md" \
  "read-only inspection does not create SCV.md"
assert_absent "$claude_project/scv/CODEX.md" \
  "read-only inspection does not create CODEX.md"

# A sync preview shows the migration but remains read-only.
output="$(
  bash "$STATE_INDEX" --project-dir "$claude_project" --dry-run --migrate 2>&1
)"
rc=$?
assert_rc "$rc" 0 "Claude migration preview succeeds"
assert_contains "$output" "MIGRATION_PREVIEW:" \
  "Claude migration preview describes SCV.md creation"
assert_absent "$claude_project/scv/SCV.md" \
  "migration preview does not create SCV.md"
assert_absent "$claude_project/scv/CODEX.md" \
  "migration preview does not create CODEX.md"

# Only an approved non-dry-run sync path performs the migration. It replaces
# the existing host file, but never invents a missing other-host pointer.
output="$(bash "$STATE_INDEX" --project-dir "$claude_project" --migrate 2>&1)"
rc=$?
assert_rc "$rc" 0 "approved Claude migration succeeds"
assert_file "$claude_project/scv/SCV.md" \
  "approved migration creates canonical SCV.md"
assert_contains "$(cat "$claude_project/scv/SCV.md")" "PROJECT: LOCAL" \
  "canonical state preserves the legacy project marker"
assert_contains "$(cat "$claude_project/scv/CLAUDE.md")" \
  "# SCV compatibility pointer for Claude Code" \
  "existing CLAUDE.md becomes a compatibility pointer"
assert_absent "$claude_project/scv/CODEX.md" \
  "Claude migration does not create an absent CODEX.md"
claude_backups=()
while IFS= read -r backup; do
  claude_backups+=("$backup")
done < <(
  find "$claude_project/.scv-backup" -type f -name CLAUDE.md 2>/dev/null
)
if [[ "${#claude_backups[@]}" -eq 1 ]] \
  && grep -qF "STATUS: N/A" "${claude_backups[0]}"; then
  ok "Claude migration keeps one recoverable legacy backup"
else
  fail "Claude migration backup is missing or does not preserve state"
fi

# Historical Codex-only state follows the same read-only and migration rules.
codex_project="$WORK/codex-only"
mkdir -p "$codex_project/scv"
printf '# existing Codex state\n\nPROJECT: LOCAL\nSTATUS: N/A\n' \
  >"$codex_project/scv/CODEX.md"
output="$(bash "$STATE_INDEX" --project-dir "$codex_project" 2>&1)"
rc=$?
assert_rc "$rc" 0 "CODEX.md-only inspection succeeds"
assert_contains "$output" "HYDRATED: yes" \
  "CODEX.md-only project is recognized as hydrated"
assert_absent "$codex_project/scv/SCV.md" \
  "CODEX.md-only inspection does not create SCV.md"
assert_absent "$codex_project/scv/CLAUDE.md" \
  "CODEX.md-only inspection does not create CLAUDE.md"

output="$(bash "$STATE_INDEX" --project-dir "$codex_project" --migrate 2>&1)"
rc=$?
assert_rc "$rc" 0 "approved Codex migration succeeds"
assert_contains "$(cat "$codex_project/scv/CODEX.md")" \
  "# SCV compatibility pointer for Codex" \
  "existing CODEX.md becomes a compatibility pointer"
assert_absent "$codex_project/scv/CLAUDE.md" \
  "Codex migration does not create an absent CLAUDE.md"

# Canonical-only state needs no host-specific pointer.
canonical_project="$WORK/canonical-only"
mkdir -p "$canonical_project/scv"
printf '# canonical\n\nPROJECT: LOCAL\nSTATUS: N/A\n' \
  >"$canonical_project/scv/SCV.md"
output="$(bash "$STATE_INDEX" --project-dir "$canonical_project" 2>&1)"
rc=$?
assert_rc "$rc" 0 "canonical-only inspection succeeds"
assert_contains "$output" "STATE_INDEX: canonical" \
  "canonical-only project is recognized"
assert_absent "$canonical_project/scv/CODEX.md" \
  "canonical inspection does not create CODEX.md"
assert_absent "$canonical_project/scv/CLAUDE.md" \
  "canonical inspection does not create CLAUDE.md"

# Divergent active indexes are never resolved implicitly, including migration.
conflict_project="$WORK/conflict"
mkdir -p "$conflict_project/scv"
printf '# canonical A\n' >"$conflict_project/scv/SCV.md"
printf '# legacy B\n' >"$conflict_project/scv/CLAUDE.md"
canonical_before="$(portable_sha256 "$conflict_project/scv/SCV.md")"
legacy_before="$(portable_sha256 "$conflict_project/scv/CLAUDE.md")"
output="$(bash "$STATE_INDEX" --project-dir "$conflict_project" --migrate 2>&1)"
rc=$?
assert_rc "$rc" 4 "divergent SCV.md and CLAUDE.md fail closed"
assert_contains "$output" "STATE_INDEX_CONFLICT:" \
  "divergent state reports an explicit conflict"
if [[ "$canonical_before" == "$(portable_sha256 "$conflict_project/scv/SCV.md")" ]] \
  && [[ "$legacy_before" == "$(portable_sha256 "$conflict_project/scv/CLAUDE.md")" ]]; then
  ok "conflict leaves both active indexes unchanged"
else
  fail "conflict changed an active state index"
fi
assert_absent "$conflict_project/.scv-backup" \
  "conflict creates no misleading backup"
assert_absent "$conflict_project/scv/CODEX.md" \
  "conflict creates no CODEX.md"

# Two different legacy hosts also require a human choice.
dual_project="$WORK/dual-legacy-conflict"
mkdir -p "$dual_project/scv"
printf '# Claude truth\n' >"$dual_project/scv/CLAUDE.md"
printf '# Codex truth\n' >"$dual_project/scv/CODEX.md"
output="$(
  bash "$STATE_INDEX" --project-dir "$dual_project" --dry-run --migrate 2>&1
)"
rc=$?
assert_rc "$rc" 4 "divergent CLAUDE.md and CODEX.md fail closed"
assert_contains "$output" "STATE_INDEX_CONFLICT:" \
  "dual legacy divergence reports an explicit conflict"
assert_absent "$dual_project/scv/SCV.md" \
  "dual legacy conflict does not create SCV.md"

# A failed core sync must happen before any legacy migration. Build a tiny
# isolated plugin-shaped fixture so failure injection cannot touch the real
# vendored core.
failure_plugin="$WORK/failure-plugin"
mkdir -p \
  "$failure_plugin/adapter/scripts" \
  "$failure_plugin/adapter/template/scv" \
  "$failure_plugin/vendor/scv-core/core/scripts"
cp "$PLUGIN_ROOT/adapter/scripts/state-index.sh" \
  "$failure_plugin/adapter/scripts/state-index.sh"
cp "$SYNC_SHIM" "$failure_plugin/adapter/scripts/sync.sh"
cp "$PLUGIN_ROOT/adapter/template/scv/CODEX.md" \
  "$failure_plugin/adapter/template/scv/CODEX.md"
cp "$PLUGIN_ROOT/adapter/template/scv/CLAUDE.md" \
  "$failure_plugin/adapter/template/scv/CLAUDE.md"
cat >"$failure_plugin/vendor/scv-core/core/scripts/sync.sh" <<'EOF'
#!/usr/bin/env bash
echo "INJECTED_CORE_SYNC_FAILURE" >&2
exit 23
EOF
chmod +x "$failure_plugin/vendor/scv-core/core/scripts/sync.sh"

failure_project="$WORK/core-sync-failure"
mkdir -p "$failure_project/scv"
printf '# existing Claude state\n\nPROJECT: LOCAL\nSTATUS: N/A\n' \
  >"$failure_project/scv/CLAUDE.md"
failure_before="$(portable_sha256 "$failure_project/scv/CLAUDE.md")"
output="$(
  bash "$failure_plugin/adapter/scripts/sync.sh" \
    --project-dir "$failure_project" 2>&1
)"
rc=$?
assert_rc "$rc" 23 "core sync failure is propagated"
assert_contains "$output" "INJECTED_CORE_SYNC_FAILURE" \
  "failure injection reached the core sync boundary"
if [[ "$failure_before" == "$(portable_sha256 "$failure_project/scv/CLAUDE.md")" ]]; then
  ok "failed core sync preserves CLAUDE.md byte-for-byte"
else
  fail "failed core sync changed CLAUDE.md"
fi
assert_absent "$failure_project/scv/SCV.md" \
  "failed core sync creates no canonical index"
assert_absent "$failure_project/scv/CODEX.md" \
  "failed core sync creates no CODEX.md"
assert_absent "$failure_project/.scv-backup" \
  "failed core sync creates no migration backup"

echo
echo "── result: $PASS passed, $FAIL failed ──"
[[ "$FAIL" -eq 0 ]]
