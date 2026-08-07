# Journal hook seam (Core 0.22.0+) — Codex registration guide

Core 0.22.0 ships two executable hook templates that capture free
conversation (turns that never invoke an `action:*`) into the committed,
author-attributed team journal `scv/journal/<YYYYMMDD>-<author>.md`:

| Vendored template | Claude Code event | Codex-equivalent moment | stdin contract |
|---|---|---|---|
| `vendor/scv-core/core/template/hooks/on-user-prompt.sh` | `UserPromptSubmit` | prompt-submit (before the turn runs) | one JSON object with a `prompt` string field |
| `vendor/scv-core/core/template/hooks/on-stop.sh` | `Stop` | turn-end / session-end | one JSON object with a `transcript_path` field pointing at a JSONL transcript |

Hook **registration is wrapper/host-owned**; Core owns only the templates and
this contract (`docs/wrapper-integration.md` §6 in `scv-core` — the same
ownership boundary as `update` and `set-models`).

## Current status in this wrapper

The self-contained Codex plugin intentionally declares **no `hooks` entry** in
`.codex-plugin/plugin.json` (the plugin contract test enforces its absence),
and the Codex plugin surface does not deliver prompt text or a JSONL
transcript path to plugin-projected commands. Registration on a Codex host is
therefore a **user/host action documented here**, not an automatic plugin
projection. This is the gap the handoff contract asks the wrapper README to
state:

- **user-prompt path**: register manually where your Codex host lets you run
  a command at prompt-submit time and can hand the adapter the prompt text.
- **on-stop path**: register only if your Codex host exposes a JSONL
  transcript path. If it does not, **omit this registration** — the seam
  contract explicitly allows partial implementation (the hook silently
  skips), and session-end protocol summaries partially compensate.

## How to register on a Codex host

1. **Adapt the host payload.** Codex event payloads are host-native; the
   templates consume the contract JSON only. Register a small adapter command
   that assembles the JSON and pipes it to the vendored template, e.g.:

   ```bash
   #!/usr/bin/env bash
   # prompt-submit adapter: $1 = the user's prompt text (host-native).
   export SCV_CORE_ROOT="<abs path>/plugins/scv/vendor/scv-core/core"
   printf '{"prompt": %s}' "$(jq -Rn --arg p "$1" '$p')" \
     | bash "$SCV_CORE_ROOT/template/hooks/on-user-prompt.sh"
   ```

   For turn-end, pipe `{"transcript_path": "<path>.jsonl"}` to
   `on-stop.sh` instead.

2. **Run with the project root as cwd.** The templates resolve `scv/`
   relative to cwd and silently no-op anywhere else (un-hydrated or non-SCV
   directories journal nothing).

3. **Export `SCV_CORE_ROOT`** (absolute path of the materialized `core/`
   directory). Without it the templates fall back to their in-payload
   relative location (`<hook dir>/../../scripts/journal-append.sh`), which is
   valid when you run the vendored files in place and broken if you copy them
   elsewhere.

4. **Preserve the non-blocking guarantee.** The templates exit `0` on every
   failure (invalid JSON, missing `prompt`, unreadable transcript, missing
   `jq`/`python3`, un-hydrated project) and write nothing. Never register
   them as blocking hooks and never promote a hook failure to a session
   failure.

5. **Never bypass redaction.** All journal writes route through
   `core/scripts/journal-append.sh`, whose redaction filter
   (password/token/secret/api-key values, `Bearer` tokens, `AKIA…` keys →
   `[REDACTED]`) runs before anything hits disk. Do not write to
   `scv/journal/` directly.

6. **Author attribution** comes from `core/scripts/lib/author.sh`
   (`git config user.name` → `GIT_AUTHOR_NAME` → `USER` → `unknown`,
   filename-slugged). To use a different identity, export `GIT_AUTHOR_NAME`
   instead of patching the templates.

SCV registers nothing by itself: no crontab edits, no daemons, no host
configuration rewrites. Registration, like scheduling, always remains the
user's action on the host.
