#!/usr/bin/env bash
# The CI splits two long jobs across runners: the vendored Core tests run in N shards and the
# vendor atomicity test runs in M parts. A split is only safe while every place that names the
# count agrees — a shard list of seven with a command that says "/8" silently skips one eighth
# of the tests. This test reads the workflow files and fails on any disagreement. It also keeps
# the Core sync bot light: the bot verifies files and opens the PR, and the PR's own checks run
# the tests once (2026-11-13: the same suite used to run in the bot and again in the PR).
#
# Run: bash plugins/scv/tests/test-ci-shards.sh

set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
ATOMICITY="$PLUGIN_ROOT/tests/test-vendor-core-atomicity.sh"

PASS=0
FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }

# How many numbers a one-line YAML list holds: "[1, 2, 3]" → 3.
list_len() {
  local body="${1#*[}"
  body="${body%%]*}"
  printf '%s\n' "$body" | tr ',' '\n' | grep -c '[0-9]'
}

# check <workflow dir> <atomicity test> → prints one line per disagreement; exit 1 when any.
check() {
  local dir="$1" atomicity="$2" ci="$1/plugin-ci.yml" sync="$1/core-sync.yml" bad=0
  local n_name n_list n_cmd m_name m_list m_cmd parts covered dup line

  # --- Core shards: job name, matrix list and command agree ---------------------
  n_name="$(grep -E 'name: Vendored SCV Core regressions \(' "$ci" | sed -E 's/.*\/([0-9]+)\).*/\1/' | head -n 1)"
  n_list="$(list_len "$(grep -E '^[[:space:]]+shard: \[' "$ci" | head -n 1)")"
  n_cmd="$(grep -E 'run-focused\.sh .*--shard ' "$ci" | sed -E 's/.*--shard [^/]*\/([0-9]+).*/\1/' | head -n 1)"
  if [[ -z "$n_name" || -z "$n_cmd" || "$n_list" == 0 ]]; then
    echo "core shards: could not read the count (name [$n_name] list [$n_list] command [$n_cmd])"; bad=1
  elif [[ "$n_name" != "$n_list" || "$n_name" != "$n_cmd" ]]; then
    echo "core shards: name says $n_name, the shard list holds $n_list, the command says $n_cmd"; bad=1
  fi
  # Every run-focused call in the PR workflow is sharded — an unsharded one runs everything again.
  if grep -E 'run-focused\.sh' "$ci" | grep -vqE -- '--shard '; then
    echo "core shards: a run-focused.sh call without --shard"; bad=1
  fi

  # --- Atomicity parts: job name, matrix list, command and the test's own table agree ----
  m_name="$(grep -E 'name: Vendor atomicity \(' "$ci" | sed -E 's/.*\/([0-9]+)\).*/\1/' | head -n 1)"
  m_list="$(list_len "$(grep -E '^[[:space:]]+part: \[' "$ci" | head -n 1)")"
  m_cmd="$(grep -E 'test-vendor-core-atomicity\.sh --part ' "$ci" | sed -E 's/.*--part [^/]*\/([0-9]+).*/\1/' | head -n 1)"
  parts="$(bash "$atomicity" --list-parts 2>/dev/null)"
  if [[ -z "$m_name" || -z "$m_cmd" || "$m_list" == 0 ]]; then
    echo "atomicity parts: could not read the count (name [$m_name] list [$m_list] command [$m_cmd])"; bad=1
  elif [[ "$m_name" != "$m_list" || "$m_name" != "$m_cmd" || "$m_name" != "$(printf '%s\n' "$parts" | grep -c .)" ]]; then
    echo "atomicity parts: name says $m_name, the part list holds $m_list, the command says $m_cmd, the test defines $(printf '%s\n' "$parts" | grep -c .)"; bad=1
  fi
  # Each section of the test belongs to exactly one part.
  covered="$(printf '%s\n' "$parts" | cut -f2 | tr ' ' '\n' | grep . | sort -n | tr '\n' ' ')"
  dup="$(printf '%s\n' "$parts" | cut -f2 | tr ' ' '\n' | grep . | sort -n | uniq -d | tr '\n' ' ')"
  if [[ "$covered" != "$(bash "$atomicity" --list-sections 2>/dev/null | cut -f1 | sort -n | tr '\n' ' ')" || -n "$dup" ]]; then
    echo "atomicity parts: the parts cover sections [$covered], repeated [$dup] — every section must be in exactly one part"; bad=1
  fi
  # Every atomicity call in a workflow names its part — a bare call runs the whole file again.
  while IFS= read -r line; do
    [[ "$line" == *"--part "* ]] || { echo "atomicity parts: a call without --part: ${line#"${line%%[![:space:]]*}"}"; bad=1; }
  done < <(grep -hE 'test-vendor-core-atomicity\.sh' "$ci" "$sync" | grep -vE '^[[:space:]]*#')

  # --- The sync bot verifies files; it does not run the test suites -----------------
  if grep -vE '^[[:space:]]*#' "$sync" | grep -qE 'run-focused\.sh|run-dry\.sh|plugins/scv/tests/test-'; then
    echo "sync bot: it runs a test suite ($(grep -vE '^[[:space:]]*#' "$sync" | grep -cE 'run-focused\.sh|run-dry\.sh|plugins/scv/tests/test-') call(s)) — the PR checks run the tests once"; bad=1
  fi
  for line in 'tools/verify-core.sh' 'bash -n' 'tools/validate-core-tree.py'; do
    grep -vE '^[[:space:]]*#' "$sync" | grep -qF -- "$line" || { echo "sync bot: the file check is gone: $line"; bad=1; }
  done
  return "$bad"
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "── the CI split agrees with itself ──"
out="$(check "$REPO_ROOT/.github/workflows" "$ATOMICITY")"; rc=$?
if [[ "$rc" -eq 0 ]]; then ok "shard count, part count and the sync bot agree"; else fail "the workflows disagree:"; printf '%s\n' "$out" | sed 's/^/      /'; fi

echo "── a change in only one place is caught ──"
mutate() {  # <name> <sed expression> <file> → exit code of check on the mutated copy
  local name="$1" expr="$2" file="$3" dir="$WORK/$1"
  mkdir -p "$dir"
  cp "$REPO_ROOT/.github/workflows/plugin-ci.yml" "$REPO_ROOT/.github/workflows/core-sync.yml" "$dir/"
  sed -E "$expr" "$dir/$file" > "$dir/$file.new" && mv "$dir/$file.new" "$dir/$file"
  cmp -s "$dir/$file" "$REPO_ROOT/.github/workflows/$file" && { echo "      (mutation $name changed nothing)"; return 9; }
  check "$dir" "$ATOMICITY" >/dev/null
}
mutate shard-list 's/^([[:space:]]+shard: \[)[0-9]+, /\1/' plugin-ci.yml
[[ $? -eq 1 ]] && ok "a shorter shard list is caught" || fail "a shorter shard list was not caught"
mutate shard-command 's/(--shard [^\/]*\/)[0-9]+/\17/' plugin-ci.yml
[[ $? -eq 1 ]] && ok "a different shard count in the command is caught" || fail "a different shard count in the command was not caught"
mutate part-list 's/^([[:space:]]+part: \[)[0-9]+, /\1/' plugin-ci.yml
[[ $? -eq 1 ]] && ok "a shorter part list is caught" || fail "a shorter part list was not caught"
mutate bare-atomicity 's/(test-vendor-core-atomicity\.sh) --part [^[:space:]]+/\1/' plugin-ci.yml
[[ $? -eq 1 ]] && ok "an atomicity call without its part is caught" || fail "an atomicity call without its part was not caught"
mutate bot-suite 's/^([[:space:]]+)(bash tools\/verify-core\.sh)$/\1\2\n\1bash plugins\/scv\/vendor\/scv-core\/core\/tests\/run-dry.sh/' core-sync.yml
rc=$?
if [[ $rc -eq 9 ]]; then
  # BSD sed keeps "\n" literal in the replacement — append the line another way.
  mkdir -p "$WORK/bot-suite2"; cp "$REPO_ROOT/.github/workflows/plugin-ci.yml" "$WORK/bot-suite2/"
  { cat "$REPO_ROOT/.github/workflows/core-sync.yml"; printf '          bash plugins/scv/vendor/scv-core/core/tests/run-dry.sh\n'; } > "$WORK/bot-suite2/core-sync.yml"
  check "$WORK/bot-suite2" "$ATOMICITY" >/dev/null; rc=$?
fi
[[ $rc -eq 1 ]] && ok "a test suite in the sync bot is caught" || fail "a test suite in the sync bot was not caught"

echo "── the atomicity test refuses a part it does not have ──"
bad_parts=0
for p in 0/3 4/3 x/3 1/2 1; do
  out="$(bash "$ATOMICITY" --part "$p" 2>&1)"; rc=$?
  [[ "$rc" -eq 2 && "$(printf '%s\n' "$out" | grep -c '✓')" -eq 0 ]] || { bad_parts=$((bad_parts + 1)); echo "      --part $p → exit $rc"; }
done
[[ "$bad_parts" -eq 0 ]] && ok "five bad part values exit 2 and run nothing" || fail "$bad_parts bad part value(s) were accepted"

echo
echo "── result: $PASS passed, $FAIL failed ──"
[[ "$FAIL" -eq 0 ]]
