#!/usr/bin/env bash
# test-workspace.sh — unit tests for scripts/lib/workspace.sh
# Self-contained: creates temp fixtures, sources the lib, asserts mode + readers.
# Run: bash tests/test-workspace.sh

set -uo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
LIB="$REPO_ROOT/scripts/lib/workspace.sh"

PASS=0
FAIL=0
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
eq()   { # eq <label> <expected> <actual>
  if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1 — expected [$2], got [$3]"; fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Helper: write a scv/CODEX.md with a SCV:WORKSPACE block carrying given fields.
make_codex() { # make_codex <dir> <repo_id> <role> <root> <workspace>
  local dir="$1" rid="$2" role="$3" root="$4" ws="$5"
  mkdir -p "$dir"
  cat > "$dir/CODEX.md" <<EOF
# scv/CODEX.md

## SCV workspace (multi-repo nesting)

<!-- SCV:WORKSPACE START -->
<!-- comment line that must be ignored by the parser -->
\`\`\`yaml
repo_id: $rid
role: $role
root: $root
workspace: $ws
\`\`\`
<!-- SCV:WORKSPACE END -->
EOF
}

run_mode() { # run_mode <codex-path> <manifest-path>
  WS_CODEX="$1" WS_MANIFEST="$2" bash -c '
    source "'"$LIB"'"
    echo "$(scv_resolve_mode)"
  '
}

run_field() { # run_field <codex-path> <fn>
  WS_CODEX="$1" bash -c '
    source "'"$LIB"'"
    '"$2"'
  '
}

echo "── workspace.sh tests ──"

# 1. No CODEX.md, no manifest → SINGLE
eq "no files → SINGLE" "SINGLE" "$(run_mode "$WORK/none/CODEX.md" "$WORK/none/WORKSPACE.yaml")"

# 2. Empty workspace block → SINGLE (default hydrated repo)
make_codex "$WORK/empty" "" "" "" ""
eq "empty block → SINGLE" "SINGLE" "$(run_mode "$WORK/empty/CODEX.md" "$WORK/empty/WORKSPACE.yaml")"

# 3. Populated root → CHILD + readers correct
make_codex "$WORK/child" "fe" "frontend" "/some/root/path" "acme"
eq "populated root → CHILD" "CHILD" "$(run_mode "$WORK/child/CODEX.md" "$WORK/child/WORKSPACE.yaml")"
eq "scv_repo_id"   "fe"               "$(run_field "$WORK/child/CODEX.md" 'scv_repo_id')"
eq "scv_role"      "frontend"         "$(run_field "$WORK/child/CODEX.md" 'scv_role')"
eq "scv_root"      "/some/root/path"  "$(run_field "$WORK/child/CODEX.md" 'scv_root')"
eq "scv_workspace" "acme"             "$(run_field "$WORK/child/CODEX.md" 'scv_workspace')"

# 4. WORKSPACE.yaml present → ROOT (wins even with empty block)
make_codex "$WORK/root" "" "" "" ""
touch "$WORK/root/WORKSPACE.yaml"
eq "manifest present → ROOT" "ROOT" "$(run_mode "$WORK/root/CODEX.md" "$WORK/root/WORKSPACE.yaml")"

# 5. graceful degrade — root path exists → reachable; bogus path + no cache → not reachable
realroot="$WORK/realroot"; mkdir -p "$realroot"
make_codex "$WORK/reach" "be" "backend" "$realroot" "acme"
WS_CODEX="$WORK/reach/CODEX.md" bash -c 'source "'"$LIB"'"; scv_root_reachable' \
  && ok "existing root path → reachable" || fail "existing root path should be reachable"

make_codex "$WORK/unreach" "be" "backend" "/no/such/dir/xyz" "acme-missing"
WS_CODEX="$WORK/unreach/CODEX.md" SCV_CACHE_DIR="$WORK/emptycache" bash -c 'source "'"$LIB"'"; scv_root_reachable' \
  && fail "missing root path should NOT be reachable" || ok "missing root path → degrade (not reachable)"

# Still CHILD even when unreachable (mode = declaration, not reachability)
eq "unreachable still CHILD" "CHILD" "$(run_mode "$WORK/unreach/CODEX.md" "$WORK/unreach/WORKSPACE.yaml")"

# 6. Detach — clear root → back to SINGLE (no migration)
make_codex "$WORK/detach" "fe" "frontend" "" ""
eq "cleared root → SINGLE (detach)" "SINGLE" "$(run_mode "$WORK/detach/CODEX.md" "$WORK/detach/WORKSPACE.yaml")"

# 7. ROOT workspace name falls back to WORKSPACE.yaml workspace_id (block empty)
make_codex "$WORK/wsname" "" "" "" ""
printf 'workspace_id: acme-platform\nmembers:\n' > "$WORK/wsname/WORKSPACE.yaml"
WSN="$(WS_CODEX="$WORK/wsname/CODEX.md" WS_MANIFEST="$WORK/wsname/WORKSPACE.yaml" bash -c 'source "'"$LIB"'"; scv_workspace')"
eq "ROOT workspace from manifest" "acme-platform" "$WSN"

echo ""
echo "── result: $PASS passed, $FAIL failed ──"
[[ "$FAIL" -eq 0 ]]
