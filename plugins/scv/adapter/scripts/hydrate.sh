#!/usr/bin/env bash
# Codex shim: run shared hydrate and inspect state without implicit migration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CORE_ROOT="$PLUGIN_ROOT/vendor/scv-core/core"
TARGET=""

[[ -x "$CORE_ROOT/scripts/hydrate.sh" ]] || {
  echo "error: vendored hydrate helper missing: $CORE_ROOT/scripts/hydrate.sh" >&2
  exit 1
}

args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  if [[ "${args[$i]}" == "init" && $((i + 1)) -lt ${#args[@]} ]]; then
    TARGET="${args[$((i + 1))]}"
    break
  fi
done
[[ -n "$TARGET" ]] || {
  echo "error: expected hydrate.sh init <target>" >&2
  exit 2
}

bash "$CORE_ROOT/scripts/hydrate.sh" "$@"
bash "$SCRIPT_DIR/state-index.sh" --project-dir "$TARGET"
