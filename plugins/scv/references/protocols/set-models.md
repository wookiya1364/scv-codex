# $scv:set-models

Inspect and migrate SCV model policy for Codex.

Claude Code allowed a different `model:` value on each command. Codex
plugin skills do not support per-skill model selection. Codex chooses the model
at the host, session, or project-config layer, so this workflow must never edit
installed `SKILL.md` files.

## Language

Use project `.env` `SCV_LANG`, then the user's latest message language, then
English. Keep model identifiers and config keys unchanged.

## Protocol

### Step 1 — Inspect compatibility input

Accept at most one legacy SCV policy:

- `recommended`
- `all-opus`
- `all-sonnet`
- `all-haiku`
- `session-default`

When no argument is supplied, inspect `SCV_MODEL_POLICY` in the project `.env`
without sourcing the file:

```bash
bash "${SCV_PLUGIN_ROOT}/scripts/apply-model-policy.sh" --from-env
```

When an argument is supplied:

```bash
bash "${SCV_PLUGIN_ROOT}/scripts/apply-model-policy.sh" --policy <resolved-policy>
```

The helper is intentionally a read-only compatibility diagnostic. Parse its
`POLICY`, `SUPPORTED`, `EFFECTIVE_POLICY`, and `CHANGED_FILES` keys.

### Step 2 — Explain the mapping

| Legacy policy | Codex interpretation |
|---|---|
| `session-default` | Already compatible; use the current Codex model. |
| `recommended` | Mixed per-command routing is unavailable; keep the session model and use normal Codex reasoning/tool behavior. |
| `all-opus` | Quality intent only; do not translate to a model name without current host evidence and user choice. |
| `all-sonnet` | Balanced intent only; do not translate automatically. |
| `all-haiku` | Economy intent only; do not translate automatically. |

Do not guess a current Codex model from an Anthropic model name.

### Step 3 — Offer scoped configuration

Read, but do not change, the effective project `.codex/config.toml` and the
current session information available from the host. Report where model
selection is currently coming from.

Only if the user explicitly asks for a durable project-wide change:

1. Verify the requested Codex model or reasoning setting is supported by the
   current host.
2. Preview the exact `.codex/config.toml` change.
3. Obtain confirmation.
4. Preserve every unrelated config key and edit only the requested setting.

If the user merely wants SCV to inherit the current session, remove or comment
out the legacy `SCV_MODEL_POLICY` line only with explicit approval. No plugin
files need to change.

## Completion

State clearly:

- the legacy policy found, if any;
- that per-skill routing cannot be reproduced by Codex plugins;
- the effective host/session behavior;
- whether any project configuration changed.
