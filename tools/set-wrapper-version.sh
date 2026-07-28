#!/usr/bin/env bash
# Set the Codex wrapper release version without changing core/template versions.

set -euo pipefail

[[ $# -eq 1 ]] || {
  echo "usage: tools/set-wrapper-version.sh <X.Y.Z-codex.N>" >&2
  exit 2
}
VERSION_VALUE="$1"
[[ "$VERSION_VALUE" =~ ^[0-9]+\.[0-9]+\.[0-9]+-codex\.[0-9]+$ ]] || {
  echo "error: invalid Codex wrapper version: $VERSION_VALUE" >&2
  exit 2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

printf '%s\n' "$VERSION_VALUE" > "$REPO_ROOT/VERSION"
printf '%s\n' "$VERSION_VALUE" > "$REPO_ROOT/plugins/scv/VERSION"

python3 - "$REPO_ROOT/plugins/scv/.codex-plugin/plugin.json" "$VERSION_VALUE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
version = sys.argv[2]
doc = json.loads(path.read_text())
doc["version"] = version
path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
PY

echo "WRAPPER_VERSION: $VERSION_VALUE"
