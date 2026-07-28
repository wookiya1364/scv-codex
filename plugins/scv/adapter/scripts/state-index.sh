#!/usr/bin/env bash
# Inspect or explicitly migrate SCV's canonical and legacy state indexes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
POINTER_TEMPLATE="$PLUGIN_ROOT/adapter/template/scv/CODEX.md"
CLAUDE_POINTER_TEMPLATE="$PLUGIN_ROOT/adapter/template/scv/CLAUDE.md"
PROJECT_DIR="$PWD"
DRY_RUN=0
MIGRATE=0
CORE_SYNC_SUCCEEDED=0

usage() {
  cat <<'EOF'
Usage: state-index.sh [--project-dir DIR] [--dry-run] [--migrate]

Without --migrate, this command is strictly read-only. Existing SCV.md,
CLAUDE.md, or CODEX.md state is recognized as hydrated. --migrate copies
legacy state into canonical SCV.md, backs up each legacy state file, and
replaces only those existing files with compatibility pointers.

--core-sync-succeeded is an internal adapter flag. It allows a successful core
sync to have advanced canonical SCV.md after it copied a verified legacy index.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir)
      [[ $# -ge 2 ]] || { echo "error: --project-dir requires a path" >&2; exit 2; }
      PROJECT_DIR="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --migrate)
      MIGRATE=1
      shift
      ;;
    --core-sync-succeeded)
      CORE_SYNC_SUCCEEDED=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

[[ -d "$PROJECT_DIR" ]] || {
  echo "error: project directory not found: $PROJECT_DIR" >&2
  exit 1
}
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
SCV_DIR="$PROJECT_DIR/scv"
CANONICAL="$SCV_DIR/SCV.md"
CLAUDE_LEGACY="$SCV_DIR/CLAUDE.md"
CODEX_LEGACY="$SCV_DIR/CODEX.md"
POINTER_MARKER="# SCV compatibility pointer"

for template in "$CLAUDE_POINTER_TEMPLATE" "$POINTER_TEMPLATE"; do
  [[ -f "$template" ]] || {
    echo "error: pointer template missing: $template" >&2
    exit 1
  }
done

is_pointer() {
  [[ -f "$1" ]] && grep -qF "$POINTER_MARKER" "$1"
}

pointer_template_for() {
  case "$(basename "$1")" in
    CLAUDE.md) printf '%s\n' "$CLAUDE_POINTER_TEMPLATE" ;;
    CODEX.md) printf '%s\n' "$POINTER_TEMPLATE" ;;
    *)
      echo "error: unsupported legacy index: $1" >&2
      return 2
      ;;
  esac
}

if [[ ! -d "$SCV_DIR" ]]; then
  echo "STATE_INDEX: not-hydrated"
  exit 0
fi

legacy_indexes=("$CLAUDE_LEGACY" "$CODEX_LEGACY")
active_legacy=()
pointer_legacy=()
for legacy in "${legacy_indexes[@]}"; do
  [[ -f "$legacy" ]] || continue
  if is_pointer "$legacy"; then
    pointer_legacy+=("$legacy")
  else
    active_legacy+=("$legacy")
  fi
done

if [[ ! -f "$CANONICAL" && ${#active_legacy[@]} -eq 0 ]]; then
  if [[ ${#pointer_legacy[@]} -gt 0 ]]; then
    echo "STATE_INDEX: broken-pointer"
    echo "error: legacy pointer exists but scv/SCV.md is missing" >&2
    exit 1
  fi
  echo "STATE_INDEX: missing"
  echo "error: none of scv/SCV.md, scv/CLAUDE.md, or scv/CODEX.md exists" >&2
  exit 1
fi

source_index="$CANONICAL"
if [[ -f "$CANONICAL" ]]; then
  echo "STATE_INDEX: canonical"
  echo "CANONICAL_INDEX: $CANONICAL"
else
  source_index="${active_legacy[0]}"
  echo "STATE_INDEX: legacy"
  echo "HYDRATED: yes"
fi

if [[ "$CORE_SYNC_SUCCEEDED" -eq 1 ]]; then
  if [[ "$MIGRATE" -ne 1 || ! -f "$CANONICAL" ]]; then
    echo "error: --core-sync-succeeded requires --migrate and canonical SCV.md" >&2
    exit 2
  fi
  legacy_baseline=""
  for legacy in "${active_legacy[@]}"; do
    echo "LEGACY_INDEX: $legacy"
    if [[ -z "$legacy_baseline" ]]; then
      legacy_baseline="$legacy"
    elif ! cmp -s "$legacy_baseline" "$legacy"; then
      echo "STATE_INDEX_CONFLICT: legacy state indexes contain different content"
      echo "CONFLICT_INDEX: $legacy_baseline"
      echo "CONFLICT_INDEX: $legacy"
      echo "MIGRATION_REQUIRED: merge or choose canonical content explicitly; no file was overwritten"
      exit 4
    fi
  done
  if [[ ${#active_legacy[@]} -gt 0 ]]; then
    echo "POST_SYNC_CANONICAL: core sync succeeded; verified legacy files may become pointers"
  fi
else
  for legacy in "${active_legacy[@]}"; do
    echo "LEGACY_INDEX: $legacy"
    if ! cmp -s "$source_index" "$legacy"; then
      echo "STATE_INDEX_CONFLICT: active state indexes contain different content"
      echo "CONFLICT_INDEX: $source_index"
      echo "CONFLICT_INDEX: $legacy"
      echo "MIGRATION_REQUIRED: merge or choose canonical content explicitly; no file was overwritten"
      exit 4
    fi
  done
fi

for pointer in "${pointer_legacy[@]}"; do
  echo "LEGACY_POINTER: $pointer"
done

if [[ "$MIGRATE" -ne 1 ]]; then
  if [[ ! -f "$CANONICAL" ]]; then
    echo "MIGRATION_AVAILABLE: an approved sync can create $CANONICAL"
  elif [[ ${#active_legacy[@]} -gt 0 ]]; then
    echo "MIGRATION_AVAILABLE: an approved sync can replace identical legacy state with pointers"
  fi
  exit 0
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  if [[ ! -f "$CANONICAL" ]]; then
    echo "MIGRATION_PREVIEW: copy $source_index -> $CANONICAL"
  fi
  for legacy in "${active_legacy[@]}"; do
    echo "POINTER_PREVIEW: replace $legacy with an SCV.md pointer"
  done
  exit 0
fi

if [[ ! -f "$CANONICAL" ]]; then
  cp "$source_index" "$CANONICAL"
  echo "CANONICAL_CREATED: $CANONICAL"
fi

if [[ ${#active_legacy[@]} -eq 0 ]]; then
  echo "MIGRATION_COMPLETE: no-legacy-state"
  exit 0
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$PROJECT_DIR/.scv-backup/$STAMP/shared-core-migration"
mkdir -p "$BACKUP_DIR"
for legacy in "${active_legacy[@]}"; do
  basename="$(basename "$legacy")"
  cp "$legacy" "$BACKUP_DIR/$basename"
  cp "$(pointer_template_for "$legacy")" "$legacy"
  echo "LEGACY_BACKUP: $BACKUP_DIR/$basename"
  echo "POINTER_CREATED: $legacy"
done

echo "MIGRATION_COMPLETE: yes"
