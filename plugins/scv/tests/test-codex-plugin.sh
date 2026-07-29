#!/usr/bin/env bash
# Structural, host-boundary, and legacy-project checks for the Codex wrapper.

set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
CORE_VENDOR="$PLUGIN_ROOT/vendor/scv-core"
CORE_ROOT="$CORE_VENDOR/core"
PROFILE="$PLUGIN_ROOT/adapter/host-profile.env"
MANIFEST="$PLUGIN_ROOT/.codex-plugin/plugin.json"
MARKETPLACE="$REPO_ROOT/.agents/plugins/marketplace.json"

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

assert_absent() {
  local path="$1" label="$2"
  if [[ ! -e "$path" ]]; then
    ok "$label"
  else
    fail "$label (unexpected: $path)"
  fi
}

assert_contains() {
  local path="$1" expected="$2" label="$3"
  if [[ -f "$path" ]] && grep -qF "$expected" "$path"; then
    ok "$label"
  else
    fail "$label (missing '$expected' in $path)"
  fi
}

assert_text_contains() {
  local text_value="$1" expected="$2" label="$3"
  if grep -qF "$expected" <<<"$text_value"; then
    ok "$label"
  else
    fail "$label (missing '$expected')"
  fi
}

assert_text_absent() {
  local text_value="$1" unwanted="$2" label="$3"
  if ! grep -qF "$unwanted" <<<"$text_value"; then
    ok "$label"
  else
    fail "$label (unexpected '$unwanted')"
  fi
}

tree_snapshot() {
  python3 - "$1" <<'PY'
import hashlib
import os
import stat
import sys
from pathlib import Path

root = Path(sys.argv[1])
digest = hashlib.sha256()
for path in sorted(root.rglob("*")):
    relative = path.relative_to(root).as_posix()
    mode = path.lstat().st_mode
    if stat.S_ISLNK(mode):
        kind = b"L"
        payload = os.readlink(path).encode()
    elif stat.S_ISDIR(mode):
        kind = b"D"
        payload = b""
    elif stat.S_ISREG(mode):
        kind = b"F"
        payload = path.read_bytes()
    else:
        kind = b"O"
        payload = b""
    digest.update(kind + b"\0" + relative.encode() + b"\0" + payload + b"\0")
print(digest.hexdigest())
PY
}

echo "── Codex wrapper package ──"

for path in \
  "$MANIFEST" \
  "$MARKETPLACE" \
  "$PLUGIN_ROOT/VERSION" \
  "$PLUGIN_ROOT/adapter/ADAPTER_API" \
  "$PROFILE" \
  "$CORE_VENDOR/VERSION" \
  "$CORE_VENDOR/CORE_API" \
  "$CORE_VENDOR/TEMPLATE_VERSION" \
  "$CORE_VENDOR/SOURCE_COMMIT" \
  "$CORE_VENDOR/core-manifest.json" \
  "$CORE_VENDOR/SHA256SUMS" \
  "$CORE_VENDOR/core.lock.json" \
  "$CORE_ROOT/manifest.json" \
  "$CORE_ROOT/actions.json" \
  "$CORE_ROOT/host-profile.env"; do
  assert_file "$path" "self-contained path ${path#"$PLUGIN_ROOT/"} exists"
done

if python3 - "$REPO_ROOT" "$PLUGIN_ROOT" "$CORE_VENDOR" <<'PY'
import json
import re
import sys
from pathlib import Path

repo = Path(sys.argv[1])
plugin = Path(sys.argv[2])
vendor = Path(sys.argv[3])
manifest = json.loads((plugin / ".codex-plugin/plugin.json").read_text())
marketplace = json.loads((repo / ".agents/plugins/marketplace.json").read_text())
lock = json.loads((vendor / "core.lock.json").read_text())

assert manifest["name"] == "scv"
assert manifest["skills"].rstrip("/") == "./skills"
assert "commands" not in manifest
assert "hooks" not in manifest
assert manifest["version"] == (plugin / "VERSION").read_text().strip()
assert manifest["version"] == (repo / "VERSION").read_text().strip()
assert re.fullmatch(r"\d+\.\d+\.\d+-codex\.\d+", manifest["version"])
assert manifest["interface"]["composerIcon"].startswith("./vendor/scv-core/")
assert manifest["interface"]["logo"].startswith("./vendor/scv-core/")

assert marketplace["name"] == "scv-codex"
entries = [entry for entry in marketplace["plugins"] if entry.get("name") == "scv"]
assert len(entries) == 1
assert entries[0]["source"] == {
    "source": "local",
    "path": "./plugins/scv",
}
assert entries[0]["policy"] == {
    "installation": "AVAILABLE",
    "authentication": "ON_INSTALL",
}

assert lock["core_version"] == (vendor / "VERSION").read_text().strip()
assert str(lock["core_api"]) == (vendor / "CORE_API").read_text().strip()
assert lock["template_version"] == (vendor / "TEMPLATE_VERSION").read_text().strip()
assert lock["artifact_sha256"] is None or re.fullmatch(
    r"[0-9a-f]{64}", lock["artifact_sha256"]
)
PY
then
  ok "manifest, marketplace, wrapper versions, and lock metadata agree"
else
  fail "manifest, marketplace, wrapper versions, or lock metadata disagree"
fi

assert_absent "$PLUGIN_ROOT/commands" \
  "legacy commands directory is absent"
for common_duplicate in scripts template assets docs ralph-template-scv.md; do
  assert_absent "$PLUGIN_ROOT/$common_duplicate" \
    "common payload is not duplicated at plugin root: $common_duplicate"
done
if git -C "$REPO_ROOT" ls-files 'plugins/scv/DeckUI/**' | grep -q .; then
  fail "tracked common payload remains at plugin root: DeckUI"
else
  ok "legacy local DeckUI output is ignored and no duplicate source is tracked"
fi
assert_absent "$PLUGIN_ROOT/references/protocols" \
  "common protocols exist only in the vendored core"

echo
echo "── action and skill boundary ──"

mapfile -t actual_skills < <(
  find "$PLUGIN_ROOT/skills" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
    | sort
)
if [[ "${actual_skills[*]}" == "${EXPECTED_SKILLS[*]}" ]]; then
  ok "skill set exactly matches the 14 core actions"
else
  fail "skill set mismatch: ${actual_skills[*]}"
fi

for skill in "${EXPECTED_SKILLS[@]}"; do
  skill_file="$PLUGIN_ROOT/skills/$skill/SKILL.md"
  agent_file="$PLUGIN_ROOT/skills/$skill/agents/openai.yaml"
  assert_file "$skill_file" "$skill: SKILL.md exists"
  assert_file "$agent_file" "$skill: agents/openai.yaml exists"

  frontmatter_name="$(
    awk '
      NR == 1 && $0 == "---" { in_frontmatter = 1; next }
      in_frontmatter && $0 == "---" { exit }
      in_frontmatter && /^name:[[:space:]]*/ {
        sub(/^name:[[:space:]]*/, "")
        print
        exit
      }
    ' "$skill_file" 2>/dev/null
  )"
  if [[ "$frontmatter_name" == "$skill" ]]; then
    ok "$skill: frontmatter name matches its directory"
  else
    fail "$skill: frontmatter name is '$frontmatter_name'"
  fi

  assert_contains "$skill_file" "../../references/codex-runtime.md" \
    "$skill: reads the Codex adapter"
  if [[ "$skill" == "update" || "$skill" == "set-models" ]]; then
    assert_contains "$skill_file" "../../adapter/protocols/$skill.md" \
      "$skill: reads its adapter-owned protocol"
  else
    assert_contains "$skill_file" \
      "../../vendor/scv-core/core/protocols/$skill.md" \
      "$skill: reads its vendored core protocol"
  fi
  assert_contains "$agent_file" "allow_implicit_invocation: true" \
    "$skill: natural-language implicit invocation is enabled"
  assert_contains "$agent_file" "\$scv:$skill" \
    "$skill: optional exact selector remains discoverable"
done

if python3 - "$CORE_ROOT/actions.json" "$PLUGIN_ROOT" <<'PY'
import json
import sys
from pathlib import Path

actions_doc = json.loads(Path(sys.argv[1]).read_text())
plugin = Path(sys.argv[2])
actions = actions_doc.get("actions", actions_doc)
if isinstance(actions, dict):
    actions = [{"id": key, **value} for key, value in actions.items()]
assert len(actions) == 14
catalog = {item["id"]: item for item in actions}
assert set(catalog) == {path.name for path in (plugin / "skills").iterdir() if path.is_dir()}
for name, action in catalog.items():
    if name in {"update", "set-models"}:
        assert action["owner"] == "adapter"
        assert action["entrypoint"] is None
    else:
        assert action["owner"] == "core"
        assert action["entrypoint"]
PY
then
  ok "core action catalog has exactly two adapter-owned actions"
else
  fail "core action ownership does not match the Codex wrapper"
fi

echo
echo "── Codex adapter contract ──"

assert_contains "$PROFILE" "SCV_ACTION_TEMPLATE='\$scv:{action}'" \
  "profile renders the optional Codex selector"
assert_contains "$PROFILE" "SCV_ARGUMENT_STYLE=argv-array" \
  "profile selects safe argv-array argument materialization"
assert_contains "$PROFILE" "SCV_STATE_INDEX=SCV.md" \
  "profile selects the shared canonical index"
assert_contains "$PROFILE" "SCV_LEGACY_STATE_INDEXES=CLAUDE.md|CODEX.md" \
  "profile recognizes both historical host indexes"
assert_contains "$CORE_ROOT/host-profile.env" "SCV_ARGUMENT_STYLE=argv-array" \
  "vendored host profile materializes Codex argument handling"
assert_contains "$CORE_ROOT/host-profile.env" \
  "SCV_LEGACY_STATE_INDEXES=CLAUDE.md|CODEX.md" \
  "vendored host profile retains cross-host legacy discovery"
assert_contains "$PLUGIN_ROOT/adapter/scripts/state-index.sh" \
  'vendor/scv-core/core/scripts/state-index.sh' \
  "state-index adapter delegates to the pinned Core resolver"
assert_contains "$PLUGIN_ROOT/adapter/scripts/state-index.sh" \
  'exec bash "$CORE_STATE_INDEX" "$@"' \
  "state-index adapter preserves the Core argv boundary"
if grep -qF 'SCV:HOST-POINTER target=SCV.md' \
  "$PLUGIN_ROOT/adapter/scripts/state-index.sh"; then
  fail "state-index adapter duplicates the Core pointer contract"
else
  ok "state-index adapter contains no second pointer resolver"
fi
assert_contains "$CORE_ROOT/scripts/state-index.sh" \
  '<!-- SCV:HOST-POINTER target=SCV.md -->' \
  "vendored Core owns the exact pointer marker"

if grep -R -nE '\{\{SCV_(ARGS|FREEFORM_ARGS|FREEFORM_TRANSPORT)\}\}' \
  "$CORE_ROOT/protocols" >/dev/null 2>&1; then
  fail "canonical argument placeholders remain unmaterialized"
else
  ok "canonical argument placeholders are materialized"
fi
if grep -R -nF '"${SCV_ARGS[@]}"' \
  "$CORE_ROOT/protocols" >/dev/null 2>&1; then
  ok "vendored protocols use safely quoted Codex argv arrays"
else
  fail "vendored protocols do not use Codex argv arrays"
fi
if grep -R -nE '\$ARGUMENTS|CLAUDE_PLUGIN_ROOT|AskUserQuestion|/scv:' \
  "$PLUGIN_ROOT/skills" "$PLUGIN_ROOT/adapter" "$CORE_ROOT/protocols"; then
  fail "current runtime files contain another host's invocation syntax"
else
  ok "current runtime files contain no Claude-only invocation syntax"
fi

assert_contains "$PLUGIN_ROOT/references/codex-runtime.md" \
  "Natural-language requests may invoke an SCV skill implicitly." \
  "runtime makes natural language the default"
assert_contains "$PLUGIN_ROOT/references/codex-runtime.md" \
  "is an optional exact selector" \
  "runtime documents the dollar selector as optional"
assert_contains "$PLUGIN_ROOT/references/codex-runtime.md" \
  "Never fetch core at runtime" \
  "runtime forbids dynamic core downloads"
assert_contains "$PLUGIN_ROOT/references/codex-runtime.md" \
  '"${SCV_ARGS[@]}"' \
  "runtime documents array-based argument passing"
assert_contains "$PLUGIN_ROOT/adapter/template/scv/CODEX.md" \
  "<!-- SCV:HOST-POINTER target=SCV.md -->" \
  "Codex pointer uses the shared pointer contract"
assert_contains "$PLUGIN_ROOT/adapter/template/scv/CLAUDE.md" \
  "<!-- SCV:HOST-POINTER target=SCV.md -->" \
  "Claude compatibility pointer uses the shared pointer contract"

echo
echo "── existing Claude project transcript ──"

if [[ -x "$PLUGIN_ROOT/adapter/scripts/hydrate.sh" \
      && -x "$CORE_ROOT/scripts/help.sh" \
      && -x "$CORE_ROOT/scripts/status.sh" \
      && -x "$CORE_ROOT/scripts/readpath.sh" \
      && -x "$PLUGIN_ROOT/adapter/scripts/sync.sh" ]]; then
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  PROJECT="$WORK/existing-claude-project"

  hydrate_output="$(
    bash "$PLUGIN_ROOT/adapter/scripts/hydrate.sh" init "$PROJECT" 2>&1
  )"
  hydrate_rc=$?
  if [[ "$hydrate_rc" -eq 0 ]]; then
    ok "materialized Codex hydrate succeeds with set -u"
  else
    fail "materialized Codex hydrate failed: $hydrate_rc"
  fi
  assert_text_contains "$hydrate_output" "\$scv:help" \
    "hydrate prints the literal optional Codex selector"
  assert_absent "$PROJECT/scv/CODEX.md" \
    "fresh hydrate does not manufacture CODEX.md"
  assert_absent "$PROJECT/scv/CLAUDE.md" \
    "fresh hydrate does not manufacture CLAUDE.md"
  mv "$PROJECT/scv/SCV.md" "$PROJECT/scv/CLAUDE.md"
  printf 'legacy raw material\n' >"$PROJECT/scv/raw/existing.txt"
  (
    cd "$PROJECT" || exit
    SCV_HOST_PROFILE="$CORE_ROOT/host-profile.env" \
      bash "$CORE_ROOT/scripts/readpath.sh" update >/dev/null
  )

  legacy_before="$(sha256sum "$PROJECT/scv/CLAUDE.md")"
  baseline_before="$(sha256sum "$PROJECT/scv/readpath.json")"
  docs_before="$(
    grep -Rl '^status: N/A$' "$PROJECT/scv" --include='*.md' | sort
  )"

  help_output="$(
    cd "$PROJECT" \
      && SCV_HOST_PROFILE="$CORE_ROOT/host-profile.env" \
        bash "$CORE_ROOT/scripts/help.sh" 2>&1
  )"
  help_rc=$?
  if [[ "$help_rc" -eq 0 ]]; then
    ok "Codex help succeeds against a CLAUDE.md-only project"
  else
    fail "Codex help failed against a CLAUDE.md-only project: $help_rc"
  fi
  assert_text_contains "$help_output" "[✓] hydrate complete" \
    "help immediately recognizes the legacy project as hydrated"
  assert_text_absent "$help_output" "hydrate not done" \
    "help does not report false missing hydration"
  assert_text_absent "$help_output" "hydrate required" \
    "help does not recommend re-hydration"
  assert_text_contains "$help_output" "\$scv:help" \
    "help prints literal Codex selectors without variable expansion"

  argument='literal $(touch HELP_INJECTION); $HOME ! * ? "quoted"'
  tree_before_argument="$(tree_snapshot "$PROJECT")"
  help_argument_output="$(
    cd "$PROJECT" \
      && SCV_HOST_PROFILE="$CORE_ROOT/host-profile.env" \
        bash "$CORE_ROOT/scripts/help.sh" "$argument" 2>&1
  )"
  help_argument_rc=$?
  tree_after_argument="$(tree_snapshot "$PROJECT")"
  if [[ "$help_argument_rc" -eq 0 ]]; then
    ok "help accepts a metacharacter-rich free-form argument"
  else
    fail "help failed for a literal free-form argument: $help_argument_rc"
  fi
  assert_text_contains "$help_argument_output" \
    "ARG_CONVERSATION: $argument" \
    "help transports free-form text literally as one argument"
  if [[ "$tree_before_argument" == "$tree_after_argument" ]]; then
    ok "help with an argument leaves the legacy project tree unchanged"
  else
    fail "help with an argument mutated the legacy project tree"
  fi
  assert_absent "$PROJECT/HELP_INJECTION" \
    "help does not evaluate command substitution from user text"
  assert_absent "$PROJECT/scv/.conversations" \
    "helper diagnosis does not create conversation state implicitly"

  status_output="$(
    cd "$PROJECT" \
      && SCV_HOST_PROFILE="$CORE_ROOT/host-profile.env" \
        bash "$CORE_ROOT/scripts/status.sh" 2>&1
  )"
  status_rc=$?
  if [[ "$status_rc" -eq 0 ]]; then
    ok "Codex status succeeds against a CLAUDE.md-only project"
  else
    fail "Codex status failed against a CLAUDE.md-only project: $status_rc"
  fi
  assert_text_contains "$status_output" "no changes since last index." \
    "status reads the existing readpath baseline"
  assert_text_contains "$status_output" "\$scv:promote" \
    "status prints literal Codex selectors without variable expansion"

  sync_output="$(
    cd "$PROJECT" \
      && SCV_HOST_PROFILE="$CORE_ROOT/host-profile.env" \
        bash "$PLUGIN_ROOT/adapter/scripts/sync.sh" \
          --project-dir "$PROJECT" --dry-run 2>&1
  )"
  sync_rc=$?
  if [[ "$sync_rc" -eq 0 ]]; then
    ok "Codex sync preview succeeds against a CLAUDE.md-only project"
  else
    fail "Codex sync preview failed against a CLAUDE.md-only project: $sync_rc"
  fi
  assert_text_contains "$sync_output" "MIGRATION_PREVIEW:" \
    "sync preview reports the optional canonical migration"

  assert_absent "$PROJECT/scv/SCV.md" \
    "help/status/sync preview do not create SCV.md"
  assert_absent "$PROJECT/scv/CODEX.md" \
    "help/status/sync preview do not create CODEX.md"
  if [[ "$legacy_before" == "$(sha256sum "$PROJECT/scv/CLAUDE.md")" ]]; then
    ok "help/status/sync preview preserve CLAUDE.md byte-for-byte"
  else
    fail "help/status/sync preview changed CLAUDE.md"
  fi
  if [[ "$baseline_before" == "$(sha256sum "$PROJECT/scv/readpath.json")" ]]; then
    ok "help/status/sync preview preserve the readpath baseline"
  else
    fail "help/status/sync preview changed the readpath baseline"
  fi
  if grep -qF "<!-- PROJECT:LOCAL START -->" "$PROJECT/scv/CLAUDE.md" \
    && grep -qF "<!-- PROJECT:LOCAL END -->" "$PROJECT/scv/CLAUDE.md"; then
    ok "legacy PROJECT:LOCAL markers remain intact"
  else
    fail "legacy PROJECT:LOCAL markers were lost"
  fi
  docs_after="$(
    grep -Rl '^status: N/A$' "$PROJECT/scv" --include='*.md' | sort
  )"
  if [[ -n "$docs_before" && "$docs_before" == "$docs_after" ]]; then
    ok "adoption-mode N/A document status remains unchanged"
  else
    fail "adoption-mode N/A document status changed"
  fi

  apply_output="$(
    cd "$PROJECT" \
      && SCV_HOST_PROFILE="$CORE_ROOT/host-profile.env" \
        bash "$PLUGIN_ROOT/adapter/scripts/sync.sh" \
          --project-dir "$PROJECT" 2>&1
  )"
  apply_rc=$?
  if [[ "$apply_rc" -eq 0 ]]; then
    ok "approved Codex sync succeeds after the read-only preview"
  else
    fail "approved Codex sync failed: $apply_rc"
    printf '%s\n' "$apply_output"
  fi
  assert_text_contains "$apply_output" "EFFECTIVE_POLICY: session-default" \
    "successful sync preserves the read-only model-policy diagnostic"
  assert_file "$PROJECT/scv/SCV.md" \
    "successful core sync creates canonical SCV.md"
  assert_contains "$PROJECT/scv/CLAUDE.md" \
    "<!-- SCV:HOST-POINTER target=SCV.md -->" \
    "successful sync replaces the existing Claude state with a pointer"
  assert_absent "$PROJECT/scv/CODEX.md" \
    "successful Claude migration still does not create CODEX.md"
  if grep -qF "<!-- PROJECT:LOCAL START -->" "$PROJECT/scv/SCV.md" \
    && grep -qF "<!-- PROJECT:LOCAL END -->" "$PROJECT/scv/SCV.md"; then
    ok "successful sync preserves PROJECT:LOCAL in canonical state"
  else
    fail "successful sync lost PROJECT:LOCAL markers"
  fi
  mapfile -t migration_backups < <(
    find "$PROJECT/.scv-backup" -type f \
      -path '*/shared-core-migration-*/CLAUDE.md' 2>/dev/null
  )
  if [[ "${#migration_backups[@]}" -eq 1 ]]; then
    ok "successful sync keeps one dedicated Claude migration backup"
  else
    fail "successful sync expected one Claude migration backup"
  fi
  if [[ "$baseline_before" == "$(sha256sum "$PROJECT/scv/readpath.json")" ]]; then
    ok "successful sync preserves the readpath baseline"
  else
    fail "successful sync changed the readpath baseline"
  fi
else
  fail "vendored core helpers needed for the Claude-project transcript are missing"
fi

echo
echo "── result: $PASS passed, $FAIL failed ──"
[[ "$FAIL" -eq 0 ]]
