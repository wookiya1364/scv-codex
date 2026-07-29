#!/usr/bin/env bash
# Transaction, runtime migration, concurrency, and race regressions for the
# Codex wrapper's maintainer-only Core vendor updater.

set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
VENDOR_TOOL="$REPO_ROOT/tools/vendor-core.sh"
TREE_STATE="$REPO_ROOT/tools/core_tree_state.py"
SOURCE_VENDOR="$PLUGIN_ROOT/vendor/scv-core"
PROFILE="$PLUGIN_ROOT/adapter/host-profile.env"

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

snapshot() {
  python3 "$TREE_STATE" snapshot --root "$1"
}

seed_vendor() {
  mkdir -p "$(dirname "$1")"
  cp -R -p "$SOURCE_VENDOR" "$1"
}

run_vendor() {
  local target=$1 output=$2 failpoint=${3:-}
  local case_root
  case_root="$(dirname "$target")"
  SCV_VENDOR_ALLOW_CUSTOM_TARGET=1 \
  SCV_VENDOR_TEST_LEGACY_DECKUI="$case_root/legacy-deckui" \
  SCV_DECK_CACHE_DIR="$case_root/deck-cache" \
  SCV_VENDOR_TEST_FAILPOINT="$failpoint" \
    bash "$VENDOR_TOOL" \
      --source "$SOURCE_VENDOR" \
      --target "$target" \
      --profile "$PROFILE" >"$output" 2>&1
}

transaction_debris() {
  local parent=$1 name=$2 candidate
  for candidate in \
    "$parent"/."$name".install.* \
    "$parent"/."$name".previous.*; do
    if [[ -e "$candidate" || -L "$candidate" ]]; then
      printf '%s\n' "$candidate"
    fi
  done
}

runtime_debris() {
  local root=$1
  [[ -e "$root" ]] || return 0
  find "$root" \
    \( \
      -name '.*.lock*' -o \
      -name '.*.stale-*' -o \
      -name '.*.stage-*' -o \
      -name '.*.install-*' \
    \) -print
}

tree_identity() {
  python3 - "$1" <<'PY'
import os
import sys

entry = os.lstat(sys.argv[1])
print(f"{entry.st_dev}:{entry.st_ino}")
PY
}

wait_for_file() {
  local path=$1 count=0
  while [[ ! -e "$path" && "$count" -lt 1000 ]]; do
    sleep 0.02
    count=$((count + 1))
  done
  [[ -e "$path" ]]
}

WORK="$(mktemp -d)"
WORK="$(cd "$WORK" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

echo "── target authority and immutable-tree validation ──"

case_root="$WORK/custom-authority"
mkdir -p "$case_root"
output="$case_root/output"
SCV_VENDOR_ALLOW_CUSTOM_TARGET=0 \
SCV_VENDOR_TEST_LEGACY_DECKUI="$case_root/legacy-deckui" \
SCV_DECK_CACHE_DIR="$case_root/deck-cache" \
  bash "$VENDOR_TOOL" \
    --source "$SOURCE_VENDOR" \
    --target "$case_root/vendor" \
    --profile "$PROFILE" >"$output" 2>&1
rc=$?
if [[ "$rc" -ne 0 ]] &&
   grep -qF "custom vendor targets require" "$output"; then
  ok "custom target requires explicit authority"
else
  fail "custom target was accepted without explicit authority"
fi
if [[ ! -e "$case_root/vendor" && ! -L "$case_root/vendor" ]]; then
  ok "unauthorized custom target causes no target write"
else
  fail "unauthorized custom target wrote a payload"
fi

case_root="$WORK/extra-file"
target="$case_root/vendor"
seed_vendor "$target"
printf 'unrelated local data\n' >"$target/immutable-sentinel"
before="$(snapshot "$target")"
output="$case_root/output"
run_vendor "$target" "$output"
rc=$?
after="$(snapshot "$target")"
if [[ "$rc" -ne 0 ]] &&
   grep -qF "untracked files" "$output"; then
  ok "unrelated file in a valid-looking vendor is rejected"
else
  fail "unrelated vendor file was accepted or misdiagnosed"
fi
if [[ "$before" == "$after" ]]; then
  ok "unrelated-file rejection preserves the vendor exactly"
else
  fail "unrelated-file rejection changed the vendor"
fi

case_root="$WORK/extra-empty-directory"
target="$case_root/vendor"
seed_vendor "$target"
mkdir -p "$target/core/empty-local-directory"
before="$(snapshot "$target")"
output="$case_root/output"
run_vendor "$target" "$output"
rc=$?
after="$(snapshot "$target")"
if [[ "$rc" -ne 0 ]] &&
   grep -qF "untracked directories" "$output"; then
  ok "unrelated empty directory is rejected"
else
  fail "unrelated empty directory was accepted or misdiagnosed"
fi
if [[ "$before" == "$after" ]]; then
  ok "empty-directory rejection preserves the vendor exactly"
else
  fail "empty-directory rejection changed the vendor"
fi

case_root="$WORK/empty-generated-directory"
target="$case_root/vendor"
seed_vendor "$target"
mkdir -p "$target/core/DeckUI/src/deck/decks/not-runtime"
before="$(snapshot "$target")"
output="$case_root/output"
run_vendor "$target" "$output"
rc=$?
after="$(snapshot "$target")"
if [[ "$rc" -ne 0 ]] &&
   grep -qF "untracked directories" "$output"; then
  ok "empty non-sample Deck directory is not mistaken for runtime"
else
  fail "empty non-sample Deck directory was silently discarded"
fi
if [[ "$before" == "$after" ]]; then
  ok "empty Deck-directory rejection preserves the source"
else
  fail "empty Deck-directory rejection changed the source"
fi

case_root="$WORK/cache-overlap"
target="$case_root/vendor"
seed_vendor "$target"
before="$(snapshot "$target")"
output="$case_root/output"
SCV_VENDOR_ALLOW_CUSTOM_TARGET=1 \
SCV_VENDOR_TEST_LEGACY_DECKUI="$case_root/legacy-deckui" \
SCV_DECK_CACHE_DIR="$target" \
  bash "$VENDOR_TOOL" \
    --source "$SOURCE_VENDOR" \
    --target "$target" \
    --profile "$PROFILE" >"$output" 2>&1
rc=$?
after="$(snapshot "$target")"
if [[ "$rc" -ne 0 ]] &&
   grep -qF "SCV Deck cache overlaps the vendor target" "$output"; then
  ok "Deck cache overlap with the vendor is rejected before migration"
else
  fail "overlapping Deck cache was accepted or misdiagnosed"
fi
if [[ "$before" == "$after" ]]; then
  ok "cache-overlap rejection performs no vendor write"
else
  fail "cache-overlap rejection changed the vendor"
fi

echo
echo "── additive Deck runtime migration ──"

case_root="$WORK/runtime-migration"
target="$case_root/vendor"
legacy="$case_root/legacy-deckui"
cache="$case_root/deck-cache"
seed_vendor "$target"
mkdir -p \
  "$target/core/DeckUI/node_modules/.pnpm/runtime/node_modules/runtime" \
  "$target/core/DeckUI/dist-deck" \
  "$legacy/scripts/deckdoc/node_modules" \
  "$legacy/src/deck/decks/user-generated"
printf 'module payload\n' \
  >"$target/core/DeckUI/node_modules/.pnpm/runtime/node_modules/runtime/index.js"
ln -s .pnpm/runtime/node_modules/runtime \
  "$target/core/DeckUI/node_modules/runtime"
printf 'built deck\n' >"$target/core/DeckUI/dist-deck/index.html"
printf 'deckdoc dependency\n' >"$legacy/scripts/deckdoc/node_modules/sentinel"
printf '{"user":"generated"}\n' \
  >"$legacy/src/deck/decks/user-generated/deck.json"
legacy_before="$(snapshot "$legacy")"
output="$case_root/output"
run_vendor "$target" "$output"
rc=$?
legacy_after="$(snapshot "$legacy")"
payload_key="$(
  python3 - "$target/core.lock.json" <<'PY'
import json
import sys
from pathlib import Path
print(json.loads(Path(sys.argv[1]).read_text())["source_payload_sha256"])
PY
)"
runtime="$cache/$payload_key/DeckUI"
if [[ "$rc" -eq 0 ]] &&
   [[ -L "$runtime/node_modules/runtime" ]] &&
   [[ -f "$runtime/node_modules/.pnpm/runtime/node_modules/runtime/index.js" ]] &&
   [[ -f "$runtime/dist-deck/index.html" ]] &&
   [[ -f "$runtime/scripts/deckdoc/node_modules/sentinel" ]] &&
   [[ -f "$runtime/src/deck/decks/user-generated/deck.json" ]]; then
  ok "vendor and legacy pnpm/build/generated Deck runtime migrates additively"
else
  fail "Deck runtime migration lost an entry or symlink"
  sed -n '1,120p' "$output"
fi
if [[ "$legacy_before" == "$legacy_after" ]]; then
  ok "legacy plugin-root DeckUI remains byte/type/mode exact"
else
  fail "legacy plugin-root DeckUI was modified"
fi
if python3 "$REPO_ROOT/tools/validate-core-tree.py" \
    --root "$target" >/dev/null 2>&1; then
  ok "installed vendor is immutable after runtime extraction"
else
  fail "installed vendor retained mutable runtime"
fi

rematerialized_candidate="$WORK/rematerialized-candidate"
rematerialized_output="$WORK/rematerialized-candidate.out"
SCV_VENDOR_ALLOW_CUSTOM_TARGET=1 \
SCV_VENDOR_TEST_LEGACY_DECKUI="$WORK/no-rematerialized-legacy" \
SCV_DECK_CACHE_DIR="$WORK/rematerialized-cache" \
  bash "$VENDOR_TOOL" \
    --source "$SOURCE_VENDOR" \
    --target "$rematerialized_candidate" \
    --profile "$PROFILE" >"$rematerialized_output" 2>&1
if [[ "$?" -ne 0 ]]; then
  echo "failed to prepare the re-materialized candidate" >&2
  sed -n '1,120p' "$rematerialized_output" >&2
  exit 1
fi

case_root="$WORK/persistent-legacy-reuse"
target="$case_root/vendor"
legacy="$case_root/legacy-deckui"
cache="$case_root/deck-cache"
authoritative="$case_root/authoritative-runtime"
seed_vendor "$target"
mkdir -p \
  "$authoritative/node_modules/pkg" \
  "$legacy/node_modules/pkg" \
  "$legacy/src/deck/decks/persistent-only"
printf 'cache-authoritative\n' \
  >"$authoritative/node_modules/pkg/index.js"
printf 'persistent-host-conflict\n' \
  >"$legacy/node_modules/pkg/index.js"
printf '{"persistent":"unique"}\n' \
  >"$legacy/src/deck/decks/persistent-only/deck.json"
if ! SCV_DECK_CACHE_DIR="$cache" \
    bash "$rematerialized_candidate/core/scripts/deck-runtime.sh" migrate \
      --from "$authoritative" >/dev/null; then
  echo "failed to prepare authoritative candidate cache" >&2
  exit 1
fi
runtime="$(
  SCV_DECK_CACHE_DIR="$cache" \
    bash "$rematerialized_candidate/core/scripts/deck-runtime.sh" path
)"
cache_before="$(snapshot "$cache")"
legacy_before="$(snapshot "$legacy")"
target_identity_before="$(tree_identity "$target")"
output="$case_root/output"
run_vendor "$target" "$output"
rc=$?
cache_after="$(snapshot "$cache")"
legacy_after="$(snapshot "$legacy")"
target_identity_after="$(tree_identity "$target")"
if [[ "$rc" -eq 0 ]] &&
   [[ "$target_identity_after" != "$target_identity_before" ]] &&
   grep -qF "SCV Core vendored successfully" "$output"; then
  ok "persistent legacy conflict reuses the authoritative cache and swaps"
else
  fail "persistent legacy cache reuse did not complete the vendor swap"
  sed -n '1,120p' "$output"
fi
if [[ "$cache_after" == "$cache_before" ]] &&
   [[ "$legacy_after" == "$legacy_before" ]]; then
  ok "persistent legacy reuse preserves cache and source byte/type/mode exact"
else
  fail "persistent legacy reuse changed the cache or legacy source"
fi
if grep -qF "cache-authoritative" \
     "$runtime/node_modules/pkg/index.js" &&
   [[ ! -e \
     "$runtime/src/deck/decks/persistent-only/deck.json" ]]; then
  ok "persistent legacy reuse does not mix a unique legacy entry"
else
  fail "persistent legacy reuse mixed or replaced authoritative runtime data"
fi
if grep -qF \
    "NOTICE: existing Deck runtime cache differs; reusing it as authoritative and skipping this legacy migration" \
    "$output"; then
  ok "persistent legacy reuse surfaces the Core reuse NOTICE"
else
  fail "persistent legacy reuse hid the Core reuse NOTICE"
fi
if [[ -z "$(transaction_debris "$case_root" vendor)" ]] &&
   [[ ! -e "$case_root/.vendor.scv-vendor.lock" ]] &&
   [[ -z "$(runtime_debris "$cache")" ]]; then
  ok "persistent legacy reuse leaves no updater or runtime debris"
else
  fail "persistent legacy reuse left transaction or runtime debris"
fi

case_root="$WORK/existing-vendor-runtime-strict"
target="$case_root/vendor"
cache="$case_root/deck-cache"
authoritative="$case_root/authoritative-runtime"
seed_vendor "$target"
mkdir -p \
  "$authoritative/node_modules/pkg" \
  "$target/core/DeckUI/node_modules/pkg"
printf 'cache-authoritative\n' \
  >"$authoritative/node_modules/pkg/index.js"
printf 'existing-vendor-conflict\n' \
  >"$target/core/DeckUI/node_modules/pkg/index.js"
if ! SCV_DECK_CACHE_DIR="$cache" \
    bash "$rematerialized_candidate/core/scripts/deck-runtime.sh" migrate \
      --from "$authoritative" >/dev/null; then
  echo "failed to prepare strict-collision cache" >&2
  exit 1
fi
target_before="$(snapshot "$target")"
cache_before="$(snapshot "$cache")"
target_identity_before="$(tree_identity "$target")"
output="$case_root/output"
run_vendor "$target" "$output"
rc=$?
target_after="$(snapshot "$target")"
cache_after="$(snapshot "$cache")"
target_identity_after="$(tree_identity "$target")"
if [[ "$rc" -ne 0 ]] &&
   grep -qF "Deck runtime migration collision" "$output" &&
   ! grep -qF "NOTICE: existing Deck runtime cache differs" "$output"; then
  ok "existing-vendor runtime collision remains strict"
else
  fail "existing-vendor collision was reused or misdiagnosed"
  sed -n '1,120p' "$output"
fi
if [[ "$target_after" == "$target_before" ]] &&
   [[ "$cache_after" == "$cache_before" ]] &&
   [[ "$target_identity_after" == "$target_identity_before" ]] &&
   [[ -z "$(transaction_debris "$case_root" vendor)" ]] &&
   [[ ! -e "$case_root/.vendor.scv-vendor.lock" ]] &&
   [[ -z "$(runtime_debris "$cache")" ]]; then
  ok "strict existing-vendor collision preserves install and recovery state"
else
  fail "strict existing-vendor collision changed install, cache, or recovery state"
fi

case_root="$WORK/runtime-migration-then-rollback"
target="$case_root/vendor"
cache="$case_root/deck-cache"
seed_vendor "$target"
mkdir -p "$target/core/DeckUI/dist-deck"
printf 'additive cache survives rollback\n' \
  >"$target/core/DeckUI/dist-deck/index.html"
before="$(snapshot "$target")"
output="$case_root/output"
run_vendor "$target" "$output" "after-backup"
rc=$?
after="$(snapshot "$target")"
runtime="$(
  find "$cache" -mindepth 2 -maxdepth 2 -type d \
    -name DeckUI -print -quit
)"
if [[ "$rc" -ne 0 && "$before" == "$after" ]] &&
   [[ -n "$runtime" && -f "$runtime/dist-deck/index.html" ]]; then
  ok "swap rollback restores source while intentional additive cache remains"
else
  fail "migration/rollback safety state is not source-exact plus additive cache"
fi

echo
echo "── rollback on failures and catchable signals ──"

failure_number=0
run_rollback_case() {
  local label=$1 failpoint=$2 case_root target output before after rc
  failure_number=$((failure_number + 1))
  case_root="$WORK/rollback-$failure_number"
  target="$case_root/vendor"
  output="$case_root/output"
  seed_vendor "$target"
  before="$(snapshot "$target")"
  run_vendor "$target" "$output" "$failpoint"
  rc=$?
  after="$(snapshot "$target")"
  if [[ "$rc" -ne 0 ]] &&
     grep -qF "previous vendor restored exactly" "$output"; then
    ok "$label: failure is propagated"
  else
    fail "$label: failure was hidden or rollback was not reported"
  fi
  if [[ "$before" == "$after" ]]; then
    ok "$label: previous vendor is restored exactly"
  else
    fail "$label: previous vendor changed"
  fi
  if [[ -z "$(transaction_debris "$case_root" vendor)" ]]; then
    ok "$label: recoverable failure leaves no transaction debris"
  else
    fail "$label: recoverable failure left transaction debris"
  fi
}

run_rollback_case "failure after backup" "after-backup"
run_rollback_case "failure after install" "after-install"
run_rollback_case "HUP after backup" "signal-HUP-after-backup"
run_rollback_case "INT after backup" "signal-INT-after-backup"
run_rollback_case "TERM after backup" "signal-TERM-after-backup"
run_rollback_case "TERM after install" "signal-TERM-after-install"

for cleanup_signal in HUP INT TERM; do
  case_root="$WORK/cleanup-signal-$cleanup_signal"
  target="$case_root/vendor"
  output="$case_root/output"
  seed_vendor "$target"
  run_vendor \
    "$target" "$output" "signal-$cleanup_signal-before-cleanup"
  rc=$?
  if [[ "$rc" -eq 0 ]] &&
     [[ -z "$(transaction_debris "$case_root" vendor)" ]]; then
    ok "$cleanup_signal during committed backup cleanup is deferred safely"
  else
    fail "$cleanup_signal interrupted committed backup cleanup"
  fi
done

echo
echo "── lock and orphan recovery ──"

case_root="$WORK/lock-create-symlink-race"
target="$case_root/vendor"
external="$case_root/external"
seed_vendor "$target"
before="$(snapshot "$target")"
mkdir -p "$external"
printf 'external owner sentinel\n' >"$external/owner"
ready="$case_root/ready"
continue_file="$case_root/continue"
output="$case_root/output"
SCV_VENDOR_ALLOW_CUSTOM_TARGET=1 \
SCV_VENDOR_TEST_LEGACY_DECKUI="$case_root/legacy-deckui" \
SCV_DECK_CACHE_DIR="$case_root/deck-cache" \
SCV_VENDOR_TEST_PAUSE_AT=after-lock-mkdir \
SCV_VENDOR_TEST_READY_FILE="$ready" \
SCV_VENDOR_TEST_CONTINUE_FILE="$continue_file" \
  bash "$VENDOR_TOOL" \
    --source "$SOURCE_VENDOR" \
    --target "$target" \
    --profile "$PROFILE" >"$output" 2>&1 &
paused_pid=$!
if wait_for_file "$ready"; then
  lock="$case_root/.vendor.scv-vendor.lock"
  preserved_lock="$case_root/preserved-new-lock"
  mv "$lock" "$preserved_lock"
  ln -s "$external" "$lock"
  printf 'continue\n' >"$continue_file"
  wait "$paused_pid"
  rc=$?
  if [[ "$rc" -ne 0 && "$(snapshot "$target")" == "$before" ]] &&
     [[ -d "$preserved_lock" && -L "$lock" ]]; then
    ok "lock creation rejects a directory-to-symlink identity swap"
  else
    fail "lock creation followed or hid a replaced lock directory"
  fi
  if [[ "$(cat "$external/owner")" == "external owner sentinel" ]]; then
    ok "lock creation cannot overwrite an external owner sentinel"
  else
    fail "lock creation overwrote an external owner through a symlink"
  fi
else
  fail "lock-creation race test never reached the mkdir pause"
fi

case_root="$WORK/concurrent"
target="$case_root/vendor"
seed_vendor "$target"
ready="$case_root/ready"
continue_file="$case_root/continue"
first_output="$case_root/first-output"
second_output="$case_root/second-output"
SCV_VENDOR_ALLOW_CUSTOM_TARGET=1 \
SCV_VENDOR_TEST_LEGACY_DECKUI="$case_root/legacy-deckui" \
SCV_DECK_CACHE_DIR="$case_root/deck-cache" \
SCV_VENDOR_TEST_HOLD_LOCK=1 \
SCV_VENDOR_TEST_READY_FILE="$ready" \
SCV_VENDOR_TEST_CONTINUE_FILE="$continue_file" \
  bash "$VENDOR_TOOL" \
    --source "$SOURCE_VENDOR" \
    --target "$target" \
    --profile "$PROFILE" >"$first_output" 2>&1 &
first_pid=$!
if wait_for_file "$ready"; then
  run_vendor "$target" "$second_output"
  second_rc=$?
  if [[ "$second_rc" -ne 0 ]] &&
     grep -qF "another Core vendor update is running" "$second_output"; then
    ok "concurrent updater is rejected by the live owner lock"
  else
    fail "concurrent updater was accepted or misdiagnosed"
  fi
else
  fail "lock-holder test process never reached the lock"
fi
printf 'continue\n' >"$continue_file"
wait "$first_pid"
first_rc=$?
if [[ "$first_rc" -eq 0 ]]; then
  ok "lock holder completes after the competing updater is rejected"
else
  fail "lock holder failed after concurrency test"
  sed -n '1,120p' "$first_output"
fi

case_root="$WORK/stale-lock"
target="$case_root/vendor"
seed_vendor "$target"
lock="$case_root/.vendor.scv-vendor.lock"
mkdir -p "$lock"
{
  printf 'pid=99999999\n'
  printf 'process_start=unknown\n'
  printf 'token=%048d\n' 0
} >"$lock/owner"
output="$case_root/output"
run_vendor "$target" "$output"
rc=$?
if [[ "$rc" -eq 0 && ! -e "$lock" && ! -L "$lock" ]]; then
  ok "well-formed stale lock is quarantined and reclaimed"
else
  fail "well-formed stale lock was not reclaimed safely"
fi

case_root="$WORK/stale-quarantine-destination-race"
target="$case_root/vendor"
seed_vendor "$target"
before="$(snapshot "$target")"
lock="$case_root/.vendor.scv-vendor.lock"
mkdir -p "$lock"
{
  printf 'pid=99999999\n'
  printf 'process_start=unknown\n'
  printf 'token=%048d\n' 0
} >"$lock/owner"
ready="$case_root/ready"
continue_file="$case_root/continue"
output="$case_root/output"
SCV_VENDOR_ALLOW_CUSTOM_TARGET=1 \
SCV_VENDOR_TEST_LEGACY_DECKUI="$case_root/legacy-deckui" \
SCV_DECK_CACHE_DIR="$case_root/deck-cache" \
SCV_VENDOR_TEST_PAUSE_AT=before-stale-lock-quarantine \
SCV_VENDOR_TEST_READY_FILE="$ready" \
SCV_VENDOR_TEST_CONTINUE_FILE="$continue_file" \
  bash "$VENDOR_TOOL" \
    --source "$SOURCE_VENDOR" \
    --target "$target" \
    --profile "$PROFILE" >"$output" 2>&1 &
paused_pid=$!
if wait_for_file "$ready"; then
  quarantine_name="$(sed -n '2p' "$ready")"
  quarantine="$case_root/$quarantine_name"
  mkdir "$quarantine"
  printf 'quarantine destination sentinel\n' >"$quarantine/sentinel"
  printf 'continue\n' >"$continue_file"
  wait "$paused_pid"
  rc=$?
  if [[ "$rc" -ne 0 && "$(snapshot "$target")" == "$before" ]] &&
     grep -qF "transaction destination already exists" "$output"; then
    ok "stale-lock quarantine uses an atomic no-replace rename"
  else
    fail "stale-lock quarantine overwrote or misdiagnosed its destination"
  fi
  if [[ -f "$lock/owner" ]] &&
     [[ "$(cat "$quarantine/sentinel")" == \
        "quarantine destination sentinel" ]]; then
    ok "quarantine collision preserves both lock and destination evidence"
  else
    fail "quarantine collision removed lock or destination evidence"
  fi
else
  fail "quarantine-destination race test never reached its pause"
fi

case_root="$WORK/stale-lock-symlink-race"
target="$case_root/vendor"
external="$case_root/external"
seed_vendor "$target"
before="$(snapshot "$target")"
lock="$case_root/.vendor.scv-vendor.lock"
mkdir -p "$lock" "$external"
{
  printf 'pid=99999999\n'
  printf 'process_start=unknown\n'
  printf 'token=%048d\n' 0
} >"$lock/owner"
printf 'external owner sentinel\n' >"$external/owner"
ready="$case_root/ready"
continue_file="$case_root/continue"
output="$case_root/output"
SCV_VENDOR_ALLOW_CUSTOM_TARGET=1 \
SCV_VENDOR_TEST_LEGACY_DECKUI="$case_root/legacy-deckui" \
SCV_DECK_CACHE_DIR="$case_root/deck-cache" \
SCV_VENDOR_TEST_PAUSE_AT=before-stale-lock-quarantine \
SCV_VENDOR_TEST_READY_FILE="$ready" \
SCV_VENDOR_TEST_CONTINUE_FILE="$continue_file" \
  bash "$VENDOR_TOOL" \
    --source "$SOURCE_VENDOR" \
    --target "$target" \
    --profile "$PROFILE" >"$output" 2>&1 &
paused_pid=$!
if wait_for_file "$ready"; then
  quarantine_name="$(sed -n '2p' "$ready")"
  quarantine="$case_root/$quarantine_name"
  preserved_lock="$case_root/preserved-stale-lock"
  mv "$lock" "$preserved_lock"
  ln -s "$external" "$lock"
  printf 'continue\n' >"$continue_file"
  wait "$paused_pid"
  rc=$?
  if [[ "$rc" -ne 0 && "$(snapshot "$target")" == "$before" ]] &&
     [[ -f "$preserved_lock/owner" && -L "$quarantine" ]]; then
    ok "stale reclaim rejects a lock-to-symlink identity swap"
  else
    fail "stale reclaim accepted or discarded a replaced lock"
  fi
  if [[ "$(cat "$external/owner")" == "external owner sentinel" ]]; then
    ok "stale reclaim cannot unlink an external owner sentinel"
  else
    fail "stale reclaim followed a lock symlink into external data"
  fi
else
  fail "stale-lock symlink race test never reached its pause"
fi

case_root="$WORK/release-lock-symlink-race"
target="$case_root/vendor"
external="$case_root/external"
seed_vendor "$target"
mkdir -p "$external"
printf 'external owner sentinel\n' >"$external/owner"
ready="$case_root/ready"
continue_file="$case_root/continue"
output="$case_root/output"
SCV_VENDOR_ALLOW_CUSTOM_TARGET=1 \
SCV_VENDOR_TEST_LEGACY_DECKUI="$case_root/legacy-deckui" \
SCV_DECK_CACHE_DIR="$case_root/deck-cache" \
SCV_VENDOR_TEST_PAUSE_AT=before-lock-release \
SCV_VENDOR_TEST_READY_FILE="$ready" \
SCV_VENDOR_TEST_CONTINUE_FILE="$continue_file" \
  bash "$VENDOR_TOOL" \
    --source "$SOURCE_VENDOR" \
    --target "$target" \
    --profile "$PROFILE" >"$output" 2>&1 &
paused_pid=$!
if wait_for_file "$ready"; then
  release_name="$(sed -n '2p' "$ready")"
  release_quarantine="$case_root/$release_name"
  lock="$case_root/.vendor.scv-vendor.lock"
  preserved_lock="$case_root/preserved-owned-lock"
  mv "$lock" "$preserved_lock"
  ln -s "$external" "$lock"
  printf 'continue\n' >"$continue_file"
  wait "$paused_pid"
  rc=$?
  if [[ "$rc" -ne 0 && -f "$preserved_lock/owner" ]] &&
     [[ -L "$release_quarantine" ]]; then
    ok "lock release rejects a lock-to-symlink identity swap"
  else
    fail "lock release accepted or discarded a replaced lock"
  fi
  if [[ "$(cat "$external/owner")" == "external owner sentinel" ]]; then
    ok "lock release cannot unlink an external owner sentinel"
  else
    fail "lock release followed a lock symlink into external data"
  fi
else
  fail "lock-release symlink race test never reached its pause"
fi

case_root="$WORK/malformed-lock"
target="$case_root/vendor"
seed_vendor "$target"
lock="$case_root/.vendor.scv-vendor.lock"
mkdir -p "$lock"
{
  printf 'pid=99999999\n'
  printf 'process_start=unknown\n'
  printf 'token=%048d\n' 0
} >"$lock/owner"
printf 'unexpected\n' >"$lock/extra"
before="$(snapshot "$target")"
output="$case_root/output"
run_vendor "$target" "$output"
rc=$?
after="$(snapshot "$target")"
if [[ "$rc" -ne 0 ]] &&
   grep -qF "unsafe or malformed Core vendor lock" "$output"; then
  ok "lock with an extra entry fails closed"
else
  fail "malformed lock was reclaimed or misdiagnosed"
fi
if [[ "$before" == "$after" && -f "$lock/extra" ]]; then
  ok "malformed lock rejection preserves target and evidence"
else
  fail "malformed lock rejection changed target or evidence"
fi

case_root="$WORK/orphan"
target="$case_root/vendor"
seed_vendor "$target"
mkdir -p "$case_root/.vendor.previous.recovery"
printf 'recovery\n' >"$case_root/.vendor.previous.recovery/sentinel"
before="$(snapshot "$target")"
output="$case_root/output"
run_vendor "$target" "$output"
rc=$?
after="$(snapshot "$target")"
if [[ "$rc" -ne 0 ]] &&
   grep -qF "unfinished Core vendor transaction" "$output"; then
  ok "orphan transaction blocks a later update"
else
  fail "orphan transaction did not fail closed"
fi
if [[ "$before" == "$after" ]] &&
   [[ -f "$case_root/.vendor.previous.recovery/sentinel" ]]; then
  ok "orphan rejection preserves vendor and recovery data"
else
  fail "orphan rejection changed vendor or recovery data"
fi

case_root="$WORK/sigkill"
target="$case_root/vendor"
seed_vendor "$target"
before="$(snapshot "$target")"
output="$case_root/output"
run_vendor "$target" "$output" "signal-KILL-after-backup"
rc=$?
backup="$(
  find "$case_root" -maxdepth 1 -type d \
    -name '.vendor.previous.*' -print -quit
)"
if [[ "$rc" -ne 0 && -n "$backup" && ! -e "$target" ]] &&
   [[ "$(snapshot "$backup")" == "$before" ]]; then
  ok "uncatchable transaction death preserves the exact backup"
else
  fail "uncatchable transaction death lost or changed the backup"
fi
second_output="$case_root/second-output"
run_vendor "$target" "$second_output"
second_rc=$?
if [[ "$second_rc" -ne 0 ]] &&
   grep -qF "unfinished Core vendor transaction" "$second_output"; then
  ok "post-SIGKILL orphan blocks future updates"
else
  fail "post-SIGKILL orphan did not fail closed"
fi

case_root="$WORK/rollback-collision"
target="$case_root/vendor"
seed_vendor "$target"
before="$(snapshot "$target")"
output="$case_root/output"
run_vendor "$target" "$output" "rollback-collision-after-install"
rc=$?
backup="$(
  find "$case_root" -maxdepth 1 -type d \
    -name '.vendor.previous.*' -print -quit
)"
if [[ "$rc" -ne 0 && -n "$backup" ]] &&
   grep -qF "rollback incomplete" "$output" &&
   [[ "$(snapshot "$backup")" == "$before" ]]; then
  ok "rollback collision preserves the exact recovery backup"
else
  fail "rollback collision hid failure or lost its backup"
fi

echo
echo "── late filesystem races ──"

case_root="$WORK/late-target-symlink"
target="$case_root/vendor"
displaced="$case_root/displaced-vendor"
external="$case_root/external"
seed_vendor "$target"
before="$(snapshot "$target")"
mkdir -p "$external"
printf 'outside target\n' >"$external/sentinel"
ready="$case_root/ready"
continue_file="$case_root/continue"
output="$case_root/output"
SCV_VENDOR_ALLOW_CUSTOM_TARGET=1 \
SCV_VENDOR_TEST_LEGACY_DECKUI="$case_root/legacy-deckui" \
SCV_DECK_CACHE_DIR="$case_root/deck-cache" \
SCV_VENDOR_TEST_PAUSE_AT=before-runtime-export \
SCV_VENDOR_TEST_READY_FILE="$ready" \
SCV_VENDOR_TEST_CONTINUE_FILE="$continue_file" \
  bash "$VENDOR_TOOL" \
    --source "$SOURCE_VENDOR" \
    --target "$target" \
    --profile "$PROFILE" >"$output" 2>&1 &
paused_pid=$!
if wait_for_file "$ready"; then
  mv "$target" "$displaced"
  ln -s "$external" "$target"
  printf 'continue\n' >"$continue_file"
  wait "$paused_pid"
  rc=$?
  external_untouched=0
  if [[ "$(cat "$external/sentinel")" == "outside target" ]] &&
     [[ ! -e "$case_root/deck-cache" ]]; then
    external_untouched=1
  fi
  unlink "$target"
  mv "$displaced" "$target"
  if [[ "$rc" -ne 0 && "$external_untouched" -eq 1 ]] &&
     [[ "$(snapshot "$target")" == "$before" ]] &&
     grep -qF "cannot open ordinary directory" "$output"; then
    ok "late target symlink cannot redirect runtime extraction or cache writes"
  else
    fail "late target symlink changed source, cache, or external data"
  fi
else
  fail "late target-symlink test never reached runtime extraction pause"
fi

case_root="$WORK/late-target-drift"
target="$case_root/vendor"
seed_vendor "$target"
ready="$case_root/ready"
continue_file="$case_root/continue"
output="$case_root/output"
SCV_VENDOR_ALLOW_CUSTOM_TARGET=1 \
SCV_VENDOR_TEST_LEGACY_DECKUI="$case_root/legacy-deckui" \
SCV_DECK_CACHE_DIR="$case_root/deck-cache" \
SCV_VENDOR_TEST_PAUSE_AT=before-swap \
SCV_VENDOR_TEST_READY_FILE="$ready" \
SCV_VENDOR_TEST_CONTINUE_FILE="$continue_file" \
  bash "$VENDOR_TOOL" \
    --source "$SOURCE_VENDOR" \
    --target "$target" \
    --profile "$PROFILE" >"$output" 2>&1 &
paused_pid=$!
if wait_for_file "$ready"; then
  printf 'concurrent target edit\n' >"$target/concurrent-edit"
  printf 'continue\n' >"$continue_file"
  wait "$paused_pid"
  rc=$?
  if [[ "$rc" -ne 0 && -f "$target/concurrent-edit" ]] &&
     grep -qF "vendor preimage changed" "$output"; then
    ok "late target drift is detected without overwriting the edit"
  else
    fail "late target drift was overwritten or misdiagnosed"
  fi
else
  fail "late target-drift test never reached the commit pause"
fi

case_root="$WORK/late-stage-drift"
target="$case_root/vendor"
seed_vendor "$target"
before="$(snapshot "$target")"
ready="$case_root/ready"
continue_file="$case_root/continue"
output="$case_root/output"
SCV_VENDOR_ALLOW_CUSTOM_TARGET=1 \
SCV_VENDOR_TEST_LEGACY_DECKUI="$case_root/legacy-deckui" \
SCV_DECK_CACHE_DIR="$case_root/deck-cache" \
SCV_VENDOR_TEST_PAUSE_AT=before-swap \
SCV_VENDOR_TEST_READY_FILE="$ready" \
SCV_VENDOR_TEST_CONTINUE_FILE="$continue_file" \
  bash "$VENDOR_TOOL" \
    --source "$SOURCE_VENDOR" \
    --target "$target" \
    --profile "$PROFILE" >"$output" 2>&1 &
paused_pid=$!
if wait_for_file "$ready"; then
  install="$(
    find "$case_root" -maxdepth 1 -type d \
      -name '.vendor.install.*' -print -quit
  )"
  printf 'late stage edit\n' >"$install/late-edit"
  printf 'continue\n' >"$continue_file"
  wait "$paused_pid"
  rc=$?
  if [[ "$rc" -ne 0 && "$(snapshot "$target")" == "$before" ]] &&
     [[ -f "$install/late-edit" ]]; then
    ok "late install-stage drift fails closed and preserves evidence"
  else
    fail "late install-stage drift changed the live target or was discarded"
  fi
else
  fail "late stage-drift test never reached the commit pause"
fi

case_root="$WORK/late-target-appearance"
target="$case_root/vendor"
mkdir -p "$case_root"
ready="$case_root/ready"
continue_file="$case_root/continue"
output="$case_root/output"
SCV_VENDOR_ALLOW_CUSTOM_TARGET=1 \
SCV_VENDOR_TEST_LEGACY_DECKUI="$case_root/legacy-deckui" \
SCV_DECK_CACHE_DIR="$case_root/deck-cache" \
SCV_VENDOR_TEST_PAUSE_AT=before-swap \
SCV_VENDOR_TEST_READY_FILE="$ready" \
SCV_VENDOR_TEST_CONTINUE_FILE="$continue_file" \
  bash "$VENDOR_TOOL" \
    --source "$SOURCE_VENDOR" \
    --target "$target" \
    --profile "$PROFILE" >"$output" 2>&1 &
paused_pid=$!
if wait_for_file "$ready"; then
  mkdir "$target"
  printf 'external target\n' >"$target/external-sentinel"
  printf 'continue\n' >"$continue_file"
  wait "$paused_pid"
  rc=$?
  if [[ "$rc" -ne 0 ]] &&
     [[ "$(cat "$target/external-sentinel")" == "external target" ]] &&
     grep -qF "vendor target appeared" "$output"; then
    ok "late target appearance is never clobbered"
  else
    fail "late target appearance was overwritten or misdiagnosed"
  fi
else
  fail "late target-appearance test never reached the commit pause"
fi

case_root="$WORK/late-target-disappearance"
target="$case_root/vendor"
displaced="$case_root/displaced-vendor"
seed_vendor "$target"
before="$(snapshot "$target")"
ready="$case_root/ready"
continue_file="$case_root/continue"
output="$case_root/output"
SCV_VENDOR_ALLOW_CUSTOM_TARGET=1 \
SCV_VENDOR_TEST_LEGACY_DECKUI="$case_root/legacy-deckui" \
SCV_DECK_CACHE_DIR="$case_root/deck-cache" \
SCV_VENDOR_TEST_PAUSE_AT=before-swap \
SCV_VENDOR_TEST_READY_FILE="$ready" \
SCV_VENDOR_TEST_CONTINUE_FILE="$continue_file" \
  bash "$VENDOR_TOOL" \
    --source "$SOURCE_VENDOR" \
    --target "$target" \
    --profile "$PROFILE" >"$output" 2>&1 &
paused_pid=$!
if wait_for_file "$ready"; then
  mv "$target" "$displaced"
  printf 'continue\n' >"$continue_file"
  wait "$paused_pid"
  rc=$?
  if [[ "$rc" -ne 0 && ! -e "$target" ]] &&
     [[ "$(snapshot "$displaced")" == "$before" ]] &&
     grep -qF "vendor target disappeared" "$output"; then
    ok "late target disappearance is detected without moving external data"
  else
    fail "late target disappearance was mishandled"
  fi
else
  fail "late target-disappearance test never reached the commit pause"
fi

case_root="$WORK/late-stage-symlink"
target="$case_root/vendor"
external="$case_root/external"
seed_vendor "$target"
before="$(snapshot "$target")"
mkdir -p "$external"
printf 'outside\n' >"$external/sentinel"
ready="$case_root/ready"
continue_file="$case_root/continue"
output="$case_root/output"
SCV_VENDOR_ALLOW_CUSTOM_TARGET=1 \
SCV_VENDOR_TEST_LEGACY_DECKUI="$case_root/legacy-deckui" \
SCV_DECK_CACHE_DIR="$case_root/deck-cache" \
SCV_VENDOR_TEST_PAUSE_AT=before-swap \
SCV_VENDOR_TEST_READY_FILE="$ready" \
SCV_VENDOR_TEST_CONTINUE_FILE="$continue_file" \
  bash "$VENDOR_TOOL" \
    --source "$SOURCE_VENDOR" \
    --target "$target" \
    --profile "$PROFILE" >"$output" 2>&1 &
paused_pid=$!
if wait_for_file "$ready"; then
  install="$(
    find "$case_root" -maxdepth 1 -type d \
      -name '.vendor.install.*' -print -quit
  )"
  moved_install="$case_root/preserved-candidate"
  mv "$install" "$moved_install"
  ln -s "$external" "$install"
  printf 'continue\n' >"$continue_file"
  wait "$paused_pid"
  rc=$?
  if [[ "$rc" -ne 0 && "$(snapshot "$target")" == "$before" ]] &&
     [[ "$(cat "$external/sentinel")" == "outside" ]] &&
     [[ -L "$install" ]]; then
    ok "late stage symlink cannot redirect cleanup outside the transaction"
  else
    fail "late stage symlink changed live or external data"
  fi
else
  fail "late stage-symlink test never reached the commit pause"
fi

case_root="$WORK/late-parent-symlink"
live_parent="$case_root/live"
moved_parent="$case_root/moved"
external="$case_root/external"
target="$live_parent/vendor"
mkdir -p "$live_parent" "$external"
seed_vendor "$target"
before="$(snapshot "$target")"
printf 'outside parent\n' >"$external/sentinel"
ready="$case_root/ready"
continue_file="$case_root/continue"
output="$case_root/output"
SCV_VENDOR_ALLOW_CUSTOM_TARGET=1 \
SCV_VENDOR_TEST_LEGACY_DECKUI="$case_root/legacy-deckui" \
SCV_DECK_CACHE_DIR="$case_root/deck-cache" \
SCV_VENDOR_TEST_PAUSE_AT=before-swap \
SCV_VENDOR_TEST_READY_FILE="$ready" \
SCV_VENDOR_TEST_CONTINUE_FILE="$continue_file" \
  bash "$VENDOR_TOOL" \
    --source "$SOURCE_VENDOR" \
    --target "$target" \
    --profile "$PROFILE" >"$output" 2>&1 &
paused_pid=$!
if wait_for_file "$ready"; then
  mv "$live_parent" "$moved_parent"
  ln -s "$external" "$live_parent"
  printf 'continue\n' >"$continue_file"
  wait "$paused_pid"
  rc=$?
  external_untouched=0
  if [[ "$(cat "$external/sentinel")" == "outside parent" ]] &&
     [[ ! -e "$external/vendor" ]]; then
    external_untouched=1
  fi
  unlink "$live_parent"
  mv "$moved_parent" "$live_parent"
  if [[ "$rc" -ne 0 && "$external_untouched" -eq 1 ]] &&
     [[ "$(snapshot "$target")" == "$before" ]] &&
     grep -qF "parent identity or type changed" "$output"; then
    ok "late parent symlink cannot redirect the FD-based transaction"
  else
    fail "late parent symlink changed live or external data"
  fi
else
  fail "late parent-symlink test never reached the commit pause"
fi

echo
echo "── result: $PASS passed, $FAIL failed ──"
[[ "$FAIL" -eq 0 ]]
