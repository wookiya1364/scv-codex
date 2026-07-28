#!/usr/bin/env bash
# Read-only comparison of the pinned core against the latest public release.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCK="$REPO_ROOT/plugins/scv/vendor/scv-core/core.lock.json"
REPOSITORY="${SCV_CORE_REPOSITORY:-wookiya1364/scv-core}"
FAIL_IF_OUTDATED=0

if [[ "${1:-}" == "--fail-if-outdated" ]]; then
  FAIL_IF_OUTDATED=1
elif [[ $# -gt 0 ]]; then
  echo "usage: tools/check-core-latest.sh [--fail-if-outdated]" >&2
  exit 2
fi

[[ -f "$LOCK" ]] || {
  echo "error: core lock not found: $LOCK" >&2
  exit 1
}

CURRENT="$(
  python3 - "$LOCK" <<'PY'
import json
import sys
from pathlib import Path
print(json.loads(Path(sys.argv[1]).read_text())["core_version"])
PY
)"

LATEST_TAG=""
if command -v gh >/dev/null 2>&1; then
  LATEST_TAG="$(gh release view --repo "$REPOSITORY" --json tagName -q .tagName 2>/dev/null || true)"
fi
if [[ -z "$LATEST_TAG" ]] && command -v curl >/dev/null 2>&1; then
  LATEST_TAG="$(
    curl --fail --location --silent --show-error \
      "https://api.github.com/repos/$REPOSITORY/releases/latest" 2>/dev/null \
      | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name", ""))' \
      || true
  )"
fi
[[ -n "$LATEST_TAG" ]] || {
  echo "error: latest scv-core release is unavailable" >&2
  exit 1
}

LATEST="${LATEST_TAG#v}"
if [[ "$CURRENT" == "$LATEST" ]]; then
  REQUIRED="no"
else
  REQUIRED="yes"
fi

echo "CURRENT_CORE_VERSION: $CURRENT"
echo "LATEST_CORE_VERSION: $LATEST"
echo "LATEST_CORE_TAG: $LATEST_TAG"
echo "UPDATE_REQUIRED: $REQUIRED"

if [[ "$REQUIRED" == "yes" && "$FAIL_IF_OUTDATED" -eq 1 ]]; then
  exit 3
fi
