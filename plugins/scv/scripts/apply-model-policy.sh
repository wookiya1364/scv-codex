#!/usr/bin/env bash
# apply-model-policy.sh — read-only Claude-to-Codex model-policy diagnostic.
#
# Codex plugins cannot select a model per skill. This helper retains the old
# CLI contract so sync and existing projects degrade safely without mutating
# installed command or skill files.

set -uo pipefail

POLICY=""
PROJECT_DIR="${SCV_PROJECT_DIR:-$PWD}"
FROM_ENV=0

valid_policy() {
  case "$1" in
    recommended|all-opus|all-sonnet|all-haiku|session-default) return 0 ;;
    *) return 1 ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --policy)
      [[ $# -ge 2 ]] || {
        echo "error: --policy requires a value" >&2
        exit 2
      }
      POLICY="$2"
      shift 2
      ;;
    --from-env)
      FROM_ENV=1
      shift
      ;;
    --project-dir)
      [[ $# -ge 2 ]] || {
        echo "error: --project-dir requires a value" >&2
        exit 2
      }
      PROJECT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "$FROM_ENV" == "1" ]]; then
  ENV_FILE="$PROJECT_DIR/.env"
  if [[ ! -f "$ENV_FILE" ]]; then
    POLICY="session-default"
  else
    POLICY="$(
      grep -E '^SCV_MODEL_POLICY=' "$ENV_FILE" 2>/dev/null \
        | tail -n1 \
        | sed 's/^SCV_MODEL_POLICY=//' \
        | tr -d "\"'" \
        | tr -d '[:space:]'
    )"
    [[ -n "$POLICY" ]] || POLICY="session-default"
  fi
fi

if [[ -z "$POLICY" ]]; then
  echo "usage: $0 --policy <recommended|all-opus|all-sonnet|all-haiku|session-default> | --from-env" >&2
  exit 2
fi

if ! valid_policy "$POLICY"; then
  echo "error: invalid policy '$POLICY'" >&2
  echo "valid: recommended | all-opus | all-sonnet | all-haiku | session-default" >&2
  exit 2
fi

if [[ "$POLICY" == "session-default" ]]; then
  supported="yes"
else
  supported="no"
fi

echo "POLICY: $POLICY"
echo "SUPPORTED: $supported"
echo "EFFECTIVE_POLICY: session-default"
echo "CHANGED_FILES: 0"
echo "NOTE: Codex model selection is controlled by the host, session, or project config; installed skills were not modified."
