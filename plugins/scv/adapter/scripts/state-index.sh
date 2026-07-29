#!/usr/bin/env bash
# Thin Codex adapter for SCV Core's host-neutral state-index contract.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CORE_STATE_INDEX="$PLUGIN_ROOT/vendor/scv-core/core/scripts/state-index.sh"
PROFILE="$PLUGIN_ROOT/adapter/host-profile.env"

[[ -x "$CORE_STATE_INDEX" ]] || {
  echo "error: pinned SCV Core state-index entrypoint is unavailable" >&2
  exit 1
}
[[ -f "$PROFILE" ]] || {
  echo "error: Codex host profile is unavailable" >&2
  exit 1
}

SCV_HOST_PROFILE="$PROFILE" exec bash "$CORE_STATE_INDEX" "$@"
