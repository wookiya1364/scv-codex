#!/usr/bin/env bash
# Verify the vendored SCV Core payload and its Codex adapter contract.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_ROOT="$REPO_ROOT/plugins/scv"
VENDOR_ROOT="$PLUGIN_ROOT/vendor/scv-core"
PROFILE="$PLUGIN_ROOT/adapter/host-profile.env"

usage() {
  echo "Usage: verify-core.sh [--vendor VENDOR_ROOT]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vendor)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      VENDOR_ROOT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

python3 "$SCRIPT_DIR/validate-core-tree.py" --root "$VENDOR_ROOT"

if [[ -x "$VENDOR_ROOT/tools/verify-core.sh" ]]; then
  bash "$VENDOR_ROOT/tools/verify-core.sh" --root "$VENDOR_ROOT"
else
  echo "error: vendored tools/verify-core.sh is missing" >&2
  exit 1
fi

python3 - "$REPO_ROOT" "$PLUGIN_ROOT" "$VENDOR_ROOT" "$PROFILE" <<'PY'
import hashlib
import json
import re
import sys
from pathlib import Path

repo = Path(sys.argv[1])
plugin = Path(sys.argv[2])
vendor = Path(sys.argv[3])
profile_path = Path(sys.argv[4])

required_vendor = [
    "VERSION",
    "CORE_API",
    "TEMPLATE_VERSION",
    "SOURCE_COMMIT",
    "SOURCE_DATE",
    "SOURCE_INFO",
    "core",
    "core-manifest.json",
    "SHA256SUMS",
    "core.lock.json",
    "core/manifest.json",
    "core/actions.json",
    "core/host-profile.env",
]
for relative in required_vendor:
    if not (vendor / relative).exists():
        raise SystemExit(f"missing vendored core contract path: {relative}")

def parse_env(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        key, sep, value = line.partition("=")
        if not sep:
            raise SystemExit(f"invalid profile line: {raw}")
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
            value = value[1:-1]
        result[key.strip()] = value
    return result

profile = parse_env(profile_path)
materialized_profile = parse_env(vendor / "core/host-profile.env")
if profile != materialized_profile:
    raise SystemExit("materialized host profile differs from adapter/host-profile.env")

expected_profile = {
    "SCV_HOST_PROFILE_API": "1",
    "SCV_HOST_ID": "codex",
    "SCV_HOST_LABEL": "Codex",
    "SCV_ACTION_TEMPLATE": "$scv:{action}",
    "SCV_ARGUMENT_STYLE": "argv-array",
    "SCV_STATE_INDEX": "SCV.md",
    "SCV_LEGACY_STATE_INDEXES": "CLAUDE.md|CODEX.md",
    "SCV_ROOT_ENV": "SCV_CORE_ROOT",
    "SCV_UPDATE_OWNER": "adapter",
    "SCV_MODEL_POLICY_OWNER": "adapter",
}
for key, expected in expected_profile.items():
    if profile.get(key) != expected:
        raise SystemExit(f"{key}: expected {expected!r}, got {profile.get(key)!r}")

state_adapter = plugin / "adapter/scripts/state-index.sh"
core_state_index = vendor / "core/scripts/state-index.sh"
if not state_adapter.is_file() or not core_state_index.is_file():
    raise SystemExit("shared state-index adapter/Core entrypoint is absent")
state_adapter_text = state_adapter.read_text()
required_delegation = (
    'CORE_STATE_INDEX="$PLUGIN_ROOT/vendor/scv-core/core/scripts/state-index.sh"',
    'SCV_HOST_PROFILE="$PROFILE" exec bash "$CORE_STATE_INDEX" "$@"',
)
for expected_line in required_delegation:
    if expected_line not in state_adapter_text.splitlines():
        raise SystemExit(
            "Codex state-index adapter does not delegate argv unchanged "
            "to the vendored Core resolver"
        )
for duplicate_resolver_token in (
    "SCV:HOST-POINTER",
    "STATE_INDEX_CONFLICT:",
    "active_legacy",
    "is_pointer()",
):
    if duplicate_resolver_token in state_adapter_text:
        raise SystemExit(
            "Codex state-index adapter duplicates Core resolver semantics: "
            f"{duplicate_resolver_token}"
        )

lock = json.loads((vendor / "core.lock.json").read_text())
required_lock = {
    "schema_version",
    "core_version",
    "core_api",
    "template_version",
    "source_repository",
    "source_commit",
    "source_manifest_sha256",
    "manifest_sha256",
    "source_payload_sha256",
    "payload_sha256",
    "artifact_sha256",
    "vendored_at",
}
missing_lock = sorted(required_lock - lock.keys())
if missing_lock:
    raise SystemExit(f"core.lock.json missing fields: {missing_lock}")

def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

core_version = (vendor / "VERSION").read_text().strip()
core_api = (vendor / "CORE_API").read_text().strip()
template_version = (vendor / "TEMPLATE_VERSION").read_text().strip()
source_commit = (vendor / "SOURCE_COMMIT").read_text().strip()
source_date = (vendor / "SOURCE_DATE").read_text().strip()
source_info = {}
for raw in (vendor / "SOURCE_INFO").read_text().splitlines():
    line = raw.strip()
    if not line or line.startswith("#"):
        continue
    key, sep, value = line.partition(":")
    if not sep or not key.strip() or not value.strip():
        raise SystemExit(f"invalid SOURCE_INFO line: {raw}")
    source_info[key.strip()] = value.strip()
source_repository = source_info.get("source_repository")
if not source_repository:
    raise SystemExit("SOURCE_INFO lacks source_repository")

manifest = json.loads((vendor / "core-manifest.json").read_text())
adapter_api = (plugin / "adapter/ADAPTER_API").read_text().strip()
if lock["schema_version"] != 1:
    raise SystemExit("unsupported core.lock.json schema_version")
if lock["core_version"] != core_version:
    raise SystemExit("lock core_version does not match VERSION")
if str(lock["core_api"]) != core_api:
    raise SystemExit("lock core_api does not match CORE_API")
if lock["template_version"] != template_version:
    raise SystemExit("lock template_version does not match TEMPLATE_VERSION")
if not re.fullmatch(r"[0-9a-f]{40}", source_commit):
    raise SystemExit("SOURCE_COMMIT must be a lowercase 40-character commit SHA")
if lock["source_commit"] != source_commit:
    raise SystemExit("lock source_commit does not match SOURCE_COMMIT")
if lock["source_repository"] != source_repository:
    raise SystemExit("lock source_repository does not match SOURCE_INFO")
if not source_date or lock["vendored_at"] != source_date:
    raise SystemExit("lock vendored_at does not match SOURCE_DATE")

expected_manifest = {
    "schema_version": 1,
    "name": "scv-core",
    "version": core_version,
    "core_api": int(core_api),
    "template_version": template_version,
    "source_repository": source_repository,
    "source_commit": source_commit,
}
for key, expected in expected_manifest.items():
    if manifest.get(key) != expected:
        raise SystemExit(
            f"core-manifest.json {key} does not match vendored provenance"
        )

hash_fields = (
    "source_manifest_sha256",
    "source_payload_sha256",
    "manifest_sha256",
    "payload_sha256",
)
for key in hash_fields:
    if not re.fullmatch(r"[0-9a-f]{64}", str(lock[key])):
        raise SystemExit(f"lock {key} must be a lowercase SHA-256")
if lock["manifest_sha256"] != sha256(vendor / "core-manifest.json"):
    raise SystemExit("lock manifest_sha256 does not match core-manifest.json")
if lock["payload_sha256"] != sha256(vendor / "SHA256SUMS"):
    raise SystemExit("lock payload_sha256 does not match SHA256SUMS")

artifact_sha256 = lock["artifact_sha256"]
if artifact_sha256 is not None and not re.fullmatch(
    r"[0-9a-f]{64}", artifact_sha256
):
    raise SystemExit("lock artifact_sha256 must be null or a lowercase SHA-256")
if core_api != adapter_api or core_api != profile["SCV_HOST_PROFILE_API"]:
    raise SystemExit("core, adapter, and host-profile API versions are incompatible")

plugin_manifest = json.loads((plugin / ".codex-plugin/plugin.json").read_text())
release_version = (plugin / "VERSION").read_text().strip()
root_release_version = (repo / "VERSION").read_text().strip()
if plugin_manifest["version"] != release_version or release_version != root_release_version:
    raise SystemExit("root, plugin, and manifest release versions differ")
wrapper_match = re.fullmatch(
    r"(\d+\.\d+\.\d+)-codex\.(\d+)", release_version
)
if not wrapper_match:
    raise SystemExit(f"unexpected Codex wrapper version: {release_version}")
actions_doc = json.loads((vendor / "core/actions.json").read_text())
actions_raw = actions_doc.get("actions", actions_doc)
if isinstance(actions_raw, list):
    actions = {entry["id"]: entry for entry in actions_raw}
elif isinstance(actions_raw, dict):
    actions = actions_raw
else:
    raise SystemExit("core/actions.json actions must be a list or object")

skill_names = sorted(path.parent.name for path in plugin.glob("skills/*/SKILL.md"))
action_names = sorted(actions)
if len(action_names) != 15:
    raise SystemExit(f"expected 15 core actions, got {len(action_names)}")
if action_names != skill_names:
    raise SystemExit(f"skill/action mismatch: actions={action_names}, skills={skill_names}")

for name, action in actions.items():
    owner = action.get("owner")
    entrypoint = action.get("entrypoint")
    if name in {"update", "set-models"}:
        if owner != "adapter" or entrypoint is not None:
            raise SystemExit(f"{name}: expected adapter owner and null entrypoint")
        protocol = plugin / f"adapter/protocols/{name}.md"
    else:
        if owner != "core":
            raise SystemExit(f"{name}: expected core owner")
        protocol = vendor / f"core/protocols/{name}.md"
    if not protocol.is_file():
        raise SystemExit(f"{name}: missing protocol {protocol}")

for agent_file in plugin.glob("skills/*/agents/openai.yaml"):
    text = agent_file.read_text()
    if "allow_implicit_invocation: true" not in text:
        raise SystemExit(f"{agent_file}: implicit invocation is not enabled")
    skill = agent_file.parents[1].name
    if f"$scv:{skill}" not in text:
        raise SystemExit(f"{agent_file}: default prompt lost exact selector")

for skill_file in plugin.glob("skills/*/SKILL.md"):
    text = skill_file.read_text()
    if "/scv:" in text:
        raise SystemExit(f"{skill_file}: forbidden slash invocation")
    name = skill_file.parent.name
    expected = (
        f"../../adapter/protocols/{name}.md"
        if name in {"update", "set-models"}
        else f"../../vendor/scv-core/core/protocols/{name}.md"
    )
    if expected not in text:
        raise SystemExit(f"{skill_file}: does not load {expected}")

materialization_tokens = (
    "{{SCV_ARGS}}",
    "{{SCV_FREEFORM_ARGS}}",
    "{{SCV_FREEFORM_TRANSPORT}}",
)
for path in (vendor / "core").rglob("*"):
    if not path.is_file() or path.suffix not in {".md", ".sh"}:
        continue
    text = path.read_text(errors="replace")
    remaining = [token for token in materialization_tokens if token in text]
    if remaining:
        raise SystemExit(
            f"{path}: unmaterialized host tokens remain: {remaining}"
        )

scannable = [
    *plugin.glob("skills/*/SKILL.md"),
    *plugin.glob("skills/*/agents/openai.yaml"),
    *plugin.glob("adapter/protocols/*.md"),
    *vendor.glob("core/protocols/*.md"),
]
for path in scannable:
    if "/scv:" in path.read_text(errors="replace"):
        raise SystemExit(f"{path}: forbidden slash invocation")

runtime = (plugin / "references/codex-runtime.md").read_text()
if "Never fetch core at runtime" not in runtime:
    raise SystemExit("Codex runtime lacks the no-runtime-fetch invariant")
if "vendor/scv-core" not in runtime:
    raise SystemExit("Codex runtime does not resolve the vendored core")

print(
    "Codex/core contract OK: "
    f"wrapper={release_version} core={core_version} "
    f"core_api={core_api} template={template_version} actions={len(actions)}"
)
PY
