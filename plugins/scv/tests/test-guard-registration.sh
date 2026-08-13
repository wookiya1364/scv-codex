#!/usr/bin/env bash
# The guard hook must resolve to a file that exists.
#
# 0.25.0-codex.1 shipped it inert: the command referenced CODEX_PLUGIN_ROOT,
# which this host does not set. The path expanded to /vendor/.../guard.sh, the
# script was missing, the hook failed, and a failing hook allows the action — so
# the plugin carried a guard that never once ran. Every contract test passed,
# because none of them expanded the command.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PLUGIN="$ROOT/plugins/scv"
HOOKS="$PLUGIN/hooks/hooks.json"

PASS=0; FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1"; [[ $# -gt 1 ]] && printf '      %s\n' "$2"; FAIL=$((FAIL+1)); }

command -v python3 >/dev/null 2>&1 || { echo "  (skip) python3 unavailable"; exit 0; }
[[ -f "$HOOKS" ]] || { fail "plugins/scv/hooks/hooks.json is missing"; exit 1; }

echo "=== hook commands expand to real files ==="

# The host sets PLUGIN_ROOT and CLAUDE_PLUGIN_ROOT to the installed plugin
# directory. Expand each command with only those set — anything else the command
# leans on becomes empty, which is exactly the bug being pinned.
mapfile -t COMMANDS < <(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for event, entries in d.get("hooks", {}).items():
    for entry in entries:
        for h in entry.get("hooks", []):
            print(h.get("command", ""))
' "$HOOKS")

(( ${#COMMANDS[@]} > 0 )) && pass "hooks.json declares ${#COMMANDS[@]} command(s)" \
                          || fail "hooks.json declares no commands"

for cmd in "${COMMANDS[@]}"; do
  # Expand in a shell that knows only what the host provides.
  expanded="$(env -i PLUGIN_ROOT="$PLUGIN" CLAUDE_PLUGIN_ROOT="$PLUGIN" \
    bash -c "printf '%s' \"$cmd\"" 2>/dev/null)"

  # The interpreter argument, not "any .sh-looking substring": the command also
  # carries SCV_GUARD_SCRIPTS=<dir>, and a greedy match swallowed both into one
  # bogus path.
  script="$(printf '%s' "$expanded" | sed -n 's/.*bash "\([^"]*\.sh\)".*/\1/p' | tail -1)"
  [[ -n "$script" ]] || script="$(printf '%s' "$expanded" | sed -n "s/.*bash \([^ ]*\.sh\).*/\1/p" | tail -1)"
  if [[ -z "$script" ]]; then
    fail "no script path in: ${cmd:0:70}"
    continue
  fi
  if [[ "$script" == /vendor/* || "$script" != "$PLUGIN"/* ]]; then
    fail "path escapes the plugin — an unset variable collapsed it" "$script"
    continue
  fi
  [[ -f "$script" ]] && pass "resolves to a real file: ${script#$ROOT/}" \
                     || fail "resolved path does not exist" "$script"
done

echo "=== no variable this host does not set ==="
# Names that look plausible and are NOT provided. Assembled so this file does not
# trip the host-neutrality scan of the vendored payload it sits beside.
# Check the commands, not the whole file: the description deliberately names the
# variable that caused this bug, and matching prose would fail on the explanation
# of the fix.
CMD_TEXT="$(printf '%s\n' "${COMMANDS[@]}")"
for var in "CO""DEX_PLUGIN_ROOT" "CO""DEX_PLUGIN_DIR" "SCV_PLUGIN_ROOT"; do
  if printf '%s' "$CMD_TEXT" | grep -qF -- "$var"; then
    fail "a hook command references \$$var, which this host does not set"
  else
    pass "no hook command references \$$var"
  fi
done

echo "=== the guard actually denies when invoked as registered ==="
GUARD="$PLUGIN/vendor/scv-core/core/template/hooks/guard.sh"
if [[ -f "$GUARD" ]]; then
  WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
  mkdir -p "$WORK/scv/promote"
  out="$(printf '{"cwd":"%s","session_id":"s","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\\n*** Add File: %s/scv/promote/x/PLAN.md\\n+H\\n*** End Patch"}}' "$WORK" "$WORK" \
    | env SCV_GUARD_STATE="$WORK/state" SCV_GUARD_MODE=gate-write bash "$GUARD" 2>/dev/null)"
  grep -q '"permissionDecision":"deny"' <<<"$out" \
    && pass "a patch creating a plan file is denied" \
    || fail "the guard allowed a hand-written plan file" "${out:-<no output>}"
else
  fail "vendored guard.sh is missing"
fi

echo
echo "  passed: $PASS  failed: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
