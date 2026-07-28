#!/usr/bin/env bash
# Structural and host-compatibility checks for the Codex-native SCV plugin.
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
MANIFEST="$PLUGIN_ROOT/.codex-plugin/plugin.json"
MARKETPLACE="$REPO_ROOT/.agents/plugins/marketplace.json"
PROTOCOL_ROOT="$PLUGIN_ROOT/references/protocols"

EXPECTED_SKILLS=(
  codegen
  deck
  handoff
  help
  install-deps
  promote
  regression
  report
  set-models
  status
  sync
  update
  work
  workspace
)

PASS=0
FAIL=0

ok() {
  echo "  ✓ $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  ✖ FAIL: $1"
  FAIL=$((FAIL + 1))
}

assert_file() {
  local path="$1" label="$2"
  if [[ -f "$path" ]]; then
    ok "$label"
  else
    fail "$label (missing: $path)"
  fi
}

assert_contains() {
  local path="$1" expected="$2" label="$3"
  if grep -qF "$expected" "$path"; then
    ok "$label"
  else
    fail "$label (missing '$expected')"
  fi
}

echo "── Codex plugin structure ──"

assert_file "$MANIFEST" "Codex plugin manifest exists"
assert_file "$MARKETPLACE" "Codex marketplace manifest exists"

if [[ -f "$MANIFEST" && -f "$MARKETPLACE" ]]; then
  if python3 - "$MANIFEST" "$MARKETPLACE" <<'PY'
import json
import re
import sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text())
marketplace = json.loads(Path(sys.argv[2]).read_text())

assert manifest["name"] == "scv"
assert re.fullmatch(
    r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)"
    r"(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?",
    manifest["version"],
)
assert manifest["skills"].rstrip("/") == "./skills"
assert "commands" not in manifest
assert "hooks" not in manifest

assert marketplace["name"] == "scv-codex"
entries = [entry for entry in marketplace["plugins"] if entry.get("name") == "scv"]
assert len(entries) == 1
entry = entries[0]
assert entry["source"] == {"source": "local", "path": "./plugins/scv"}
assert entry["policy"] == {
    "installation": "AVAILABLE",
    "authentication": "ON_INSTALL",
}
assert entry["category"] == "Productivity"
PY
  then
    ok "manifest and marketplace metadata satisfy the Codex contract"
  else
    fail "manifest or marketplace metadata violates the Codex contract"
  fi
fi

if [[ ! -d "$PLUGIN_ROOT/commands" ]]; then
  ok "legacy commands/ directory is absent"
else
  fail "legacy commands/ directory must be removed to avoid partial migration"
fi

mapfile -t actual_skills < <(
  find "$PLUGIN_ROOT/skills" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
)
if [[ "${actual_skills[*]}" == "${EXPECTED_SKILLS[*]}" ]]; then
  ok "Codex skill set exactly matches the 14 SCV workflows"
else
  fail "skill set mismatch: expected '${EXPECTED_SKILLS[*]}', got '${actual_skills[*]}'"
fi

echo
echo "── Skill wrappers and protocols ──"

for skill in "${EXPECTED_SKILLS[@]}"; do
  skill_file="$PLUGIN_ROOT/skills/$skill/SKILL.md"
  agent_file="$PLUGIN_ROOT/skills/$skill/agents/openai.yaml"
  protocol_file="$PROTOCOL_ROOT/$skill.md"

  assert_file "$skill_file" "$skill: SKILL.md exists"
  assert_file "$agent_file" "$skill: agents/openai.yaml exists"
  assert_file "$protocol_file" "$skill: protocol exists"

  [[ -f "$skill_file" ]] || continue

  frontmatter_name="$(
    awk '
      NR == 1 && $0 == "---" { in_frontmatter = 1; next }
      in_frontmatter && $0 == "---" { exit }
      in_frontmatter && /^name:[[:space:]]*/ {
        sub(/^name:[[:space:]]*/, "")
        print
        exit
      }
    ' "$skill_file"
  )"
  if [[ "$frontmatter_name" == "$skill" ]]; then
    ok "$skill: frontmatter name matches directory"
  else
    fail "$skill: frontmatter name is '$frontmatter_name'"
  fi

  if awk '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter && /^description:[[:space:]]*[^[:space:]]/ { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$skill_file"; then
    ok "$skill: frontmatter has a non-empty description"
  else
    fail "$skill: frontmatter description is missing or empty"
  fi

  if awk '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter && /^(model|allowed-tools|argument-hint):/ { bad = 1 }
    END { exit bad ? 1 : 0 }
  ' "$skill_file"; then
    ok "$skill: frontmatter uses only Codex-supported fields"
  else
    fail "$skill: legacy Claude frontmatter field remains"
  fi

  assert_contains "$skill_file" "../../references/codex-runtime.md" \
    "$skill: loads shared Codex runtime guidance"
  assert_contains "$skill_file" "../../references/protocols/$skill.md" \
    "$skill: loads its workflow protocol"
  if [[ -f "$agent_file" ]]; then
    assert_contains "$agent_file" "\$scv:$skill" \
      "$skill: default prompt uses Codex plugin identity"
  fi
done

echo
echo "── Host migration guards ──"

forbidden_pattern='CLAUDE_PLUGIN_ROOT|\$ARGUMENTS|AskUserQuestion|/scv:|\.claude/settings|Claude Code skill|You — Claude|^(model|allowed-tools|argument-hint):'
if grep -R -nE "$forbidden_pattern" "$PLUGIN_ROOT/skills" "$PROTOCOL_ROOT"; then
  fail "Codex skills or protocols still contain Claude-only host syntax"
else
  ok "Codex skills and protocols contain no Claude-only host syntax"
fi

assert_contains "$PROTOCOL_ROOT/set-models.md" \
  "plugin skills do not support per-skill model selection" \
  "set-models documents the Codex model boundary"
assert_contains "$PROTOCOL_ROOT/set-models.md" \
  ".codex/config.toml" \
  "set-models scopes durable model changes to project config"
assert_contains "$PROTOCOL_ROOT/set-models.md" \
  "Only if the user explicitly asks" \
  "set-models requires an explicit project-wide request"
assert_contains "$PROTOCOL_ROOT/update.md" \
  "codex plugin marketplace upgrade" \
  "update uses the Codex marketplace refresh command"
assert_contains "$PROTOCOL_ROOT/update.md" \
  "codex plugin add" \
  "update uses the Codex plugin install command"
assert_contains "$PROTOCOL_ROOT/update.md" \
  "start a new Codex chat or CLI session" \
  "update explains the new-session activation boundary"

echo
echo "── result: $PASS passed, $FAIL failed ──"
[[ "$FAIL" -eq 0 ]]
