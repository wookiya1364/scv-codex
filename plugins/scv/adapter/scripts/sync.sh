#!/usr/bin/env bash
# Codex shim: migrate legacy state only during an approved, non-dry-run sync.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CORE_ROOT="$PLUGIN_ROOT/vendor/scv-core/core"
PROJECT_DIR="$PWD"
DRY_RUN=0
ARGS=("$@")

[[ -x "$CORE_ROOT/scripts/sync.sh" ]] || {
  echo "error: vendored sync helper missing: $CORE_ROOT/scripts/sync.sh" >&2
  exit 1
}

for ((i = 0; i < ${#ARGS[@]}; i++)); do
  case "${ARGS[$i]}" in
    --project-dir)
      [[ $((i + 1)) -lt ${#ARGS[@]} ]] || {
        echo "error: --project-dir requires a path" >&2
        exit 2
      }
      PROJECT_DIR="${ARGS[$((i + 1))]}"
      i=$((i + 1))
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
  esac
done

if [[ "$DRY_RUN" -eq 1 ]]; then
  bash "$SCRIPT_DIR/state-index.sh" \
    --project-dir "$PROJECT_DIR" --dry-run --migrate
  bash "$CORE_ROOT/scripts/sync.sh" "$@"
else
  # Revalidate without writes immediately before the approved apply. The core
  # helper must complete before any legacy file is backed up or pointerized.
  bash "$SCRIPT_DIR/state-index.sh" \
    --project-dir "$PROJECT_DIR" --dry-run --migrate
  bash "$CORE_ROOT/scripts/sync.sh" "$@"
  bash "$SCRIPT_DIR/state-index.sh" \
    --project-dir "$PROJECT_DIR" --migrate --core-sync-succeeded
  bash "$SCRIPT_DIR/state-index.sh" --project-dir "$PROJECT_DIR"
  echo
  echo "Model policy (from .env SCV_MODEL_POLICY):"
  SCV_PROJECT_DIR="$PROJECT_DIR" \
    bash "$SCRIPT_DIR/apply-model-policy.sh" --from-env 2>&1 | sed 's/^/  /'
fi
