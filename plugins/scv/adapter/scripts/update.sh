#!/usr/bin/env bash
# update.sh — read-only SCV Codex plugin version diagnostic.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PLUGIN_JSON="$PLUGIN_ROOT/.codex-plugin/plugin.json"

json_string() {
  local key="$1" file="$2"
  grep -m1 "\"$key\"" "$file" 2>/dev/null \
    | sed -E "s/.*\"$key\":[[:space:]]*\"([^\"]+)\".*/\\1/"
}

INSTALLED_VERSION="(not found)"
PLUGIN_NAME="(unknown)"
MARKETPLACE_NAME="${SCV_MARKETPLACE_NAME:-scv-codex}"
REPO=""

if [[ -f "$PLUGIN_JSON" ]]; then
  value="$(json_string version "$PLUGIN_JSON")"
  [[ -n "$value" ]] && INSTALLED_VERSION="$value"
  value="$(json_string name "$PLUGIN_JSON")"
  [[ -n "$value" ]] && PLUGIN_NAME="$value"
  value="$(json_string repository "$PLUGIN_JSON")"
  [[ -n "$value" ]] && REPO="$value"
  if [[ -z "$REPO" ]]; then
    value="$(json_string homepage "$PLUGIN_JSON")"
    [[ -n "$value" ]] && REPO="$value"
  fi
fi

# Prefer the marketplace recorded by the current Codex installation.
if command -v codex >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  detected="$(
    codex plugin list --json 2>/dev/null \
      | jq -r --arg name "$PLUGIN_NAME" '
          (.installed // [])
          | map(select(.name == $name))
          | first
          | .marketplaceName // empty
        ' 2>/dev/null
  )"
  [[ -n "$detected" ]] && MARKETPLACE_NAME="$detected"
fi

REPO="$(printf '%s' "$REPO" | sed -E 's|https?://github.com/||; s|\.git$||; s|/$||')"

echo "INSTALLED_VERSION: $INSTALLED_VERSION"
echo "MARKETPLACE_NAME: $MARKETPLACE_NAME"
echo "PLUGIN_NAME: $PLUGIN_NAME"

if [[ -z "$REPO" ]]; then
  echo "LATEST_VERSION: (unavailable — repository not parseable from plugin.json)"
  echo "UP_TO_DATE: unknown"
elif ! command -v gh >/dev/null 2>&1; then
  echo "LATEST_VERSION: (unavailable — gh CLI not installed; visit https://github.com/$REPO/releases)"
  echo "UP_TO_DATE: unknown"
else
  tag="$(gh release view --repo "$REPO" --json tagName -q '.tagName' 2>/dev/null | sed 's/^v//')"
  if [[ -z "$tag" ]]; then
    echo "LATEST_VERSION: (unavailable — no readable GitHub release; check gh auth status or https://github.com/$REPO/releases)"
    echo "UP_TO_DATE: unknown"
  else
    echo "LATEST_VERSION: $tag"
    if [[ "$INSTALLED_VERSION" == "$tag" ]]; then
      echo "UP_TO_DATE: yes"
    else
      echo "UP_TO_DATE: no"
    fi
  fi
fi

exit 0
