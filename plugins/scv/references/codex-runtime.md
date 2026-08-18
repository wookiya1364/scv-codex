# Codex adapter for SCV Core

Apply this adapter before reading an SCV protocol. The vendored core is the
workflow source of truth; this file only defines Codex runtime behavior.

## Resolve the self-contained plugin

1. Resolve the active skill's absolute `SKILL.md` path from the metadata Codex
   loaded.
2. Set `SCV_PLUGIN_ROOT` to the directory two levels above the skill folder.
3. Set:

   ```bash
   SCV_CORE_VENDOR="$SCV_PLUGIN_ROOT/vendor/scv-core"
   SCV_CORE_ROOT="$SCV_CORE_VENDOR/core"
   ```

4. Before running a helper, validate these files exist:

   - `$SCV_PLUGIN_ROOT/.codex-plugin/plugin.json`
   - `$SCV_CORE_VENDOR/core.lock.json`
   - `$SCV_CORE_VENDOR/SHA256SUMS`
   - `$SCV_CORE_ROOT/manifest.json`
   - `$SCV_CORE_ROOT/actions.json`
   - `$SCV_CORE_ROOT/host-profile.env`

Never fetch core at runtime and never assume a source-checkout path. The
installed plugin must work from its own cache directory without network access.
Use absolute, quoted paths for shared helpers, with `$SCV_CORE_ROOT` already
substituted for its value in the command you actually run — the guard matches
that directory as a fixed string, so a command still carrying the variable mints
no receipt (see "Guard receipts" below):

```bash
bash "<resolved SCV_CORE_ROOT>/scripts/help.sh"
```

The two adapter-owned actions use plugin-local helpers:

```bash
bash "$SCV_PLUGIN_ROOT/adapter/scripts/update.sh"
bash "$SCV_PLUGIN_ROOT/adapter/scripts/apply-model-policy.sh" --from-env
```

Codex also owns compatibility shims around the shared state index. Whenever a
vendored protocol asks to hydrate or sync, use these paths instead of calling
the corresponding core helper directly:

```bash
bash "$SCV_PLUGIN_ROOT/adapter/scripts/hydrate.sh" init .
bash "$SCV_PLUGIN_ROOT/adapter/scripts/sync.sh" --project-dir "$(pwd)" --dry-run
```

The canonical index is `scv/SCV.md`. Existing `scv/CLAUDE.md` or
`scv/CODEX.md` state also means the project is already hydrated. Read-only
actions must not recommend re-hydration, create a pointer, or migrate state.
Only an explicitly approved, non-dry-run sync may copy legacy state into
`SCV.md`; it backs up and replaces only the legacy files that already exist.
If active indexes differ, stop with a conflict instead of choosing one.
After a successful apply, the Codex sync shim also runs the adapter's
read-only legacy model-policy diagnostic; it never rewrites installed skills.

## Guard receipts

The workspace guard is a `PreToolUse` hook. Without a receipt it denies two
writes: creating a plan file under `scv/promote/<slug>/`, and writing to a
non-exempt path outside `scv/`. This host registers `gate-bash` and `gate-write`
only — Codex has no skill-invocation event, so there is no mint entry, and a
shell call is the only thing that can mint a receipt here.

`hooks/hooks.json` gives the hook two directories to watch — the vendored
`$SCV_CORE_ROOT/scripts` AND `$SCV_PLUGIN_ROOT/adapter/scripts`, colon-separated
(Core 0.28.0 taught `SCV_GUARD_SCRIPTS` to take a list) — and the hook looks for
each in the command text as a fixed string. Two things follow:

- The adapter helpers above mint exactly like the Core ones now. This closes
  what shipped as a known gap: with a single directory listed, `$scv:update`,
  `$scv:set-models`, `$scv:sync` and the hydrate shim ran their scripts and
  minted nothing, which `core/contracts/guard.md` — "an adapter script
  directory must be part of the mint allowlist" — required and this host could
  not express. `test-guard-registration.sh` asserts both directories mint.
- A command that reaches a core helper through an unexpanded variable carries the
  variable, not the directory, so it does not match either. Let the resolved path
  stand in the command you run.

What the user sees: the adapter-routed action finishes normally, the session
still holds no receipt, and the next source edit is refused — "no SCV action has
run in this session". Say it in that order: the action ran, the guard never saw
it. Then offer a core action such as `$scv:status`, which calls a vendored helper
and clears the block for the rest of the session. Do not disable the guard and do
not edit the hook to route around this.

## Parse invocation arguments

- Natural-language requests may invoke an SCV skill implicitly.
- `$scv:<name>` is an optional exact selector, not a slash command.
- For an exact selector, treat the text after it as that skill's arguments.
- For an implicit invocation, infer arguments only when the request makes them
  unambiguous.
- Build a shell array named `SCV_ARGS`; pass it as `"${SCV_ARGS[@]}"`.
- Vendored protocols materialize the neutral `{{SCV_ARGS}}` token as
  `"${SCV_ARGS[@]}"` for this adapter. Do not replace it with an arbitrary
  expression field.
- Free-form help text uses the same array transport. Pass each parsed element
  literally; the helper joins it for diagnosis and must never evaluate it.
- Never concatenate untrusted input into a shell string and never use `eval`.
- Ask one concise question when a required slug, phase, target, or choice
  cannot be discovered safely.

Vendored protocols may use the neutral token `action:<name>`. Present that token
to the user as `$scv:<name>`. Do not reinterpret it as a shell command.

## Map host capabilities

| Core term | Codex behavior |
|---|---|
| user decision | ask concisely; use structured input when the current surface provides it |
| shell, read, search, write, edit | use the equivalent current Codex tools |
| optional skill | use it only when installed; otherwise follow the documented fallback |
| deep/balanced/economy execution class | treat as intent only; Codex model selection remains host/session controlled |

Codex plugin skills cannot pin a model per skill. Never rewrite installed skill
files to emulate another host's model routing.

## Language

Use this priority for user-facing prose:

1. Project `.env` `SCV_LANG`.
2. The language of the user's latest message.
3. English.

Treat settings from another host only as optional migration input.

## Safety and completion

- Keep filesystem changes inside the active project unless the user explicitly
  scopes another path.
- Preserve unrelated worktree changes.
- Preview dependency installation, template sync, workspace detach, remote
  push, PR/MR creation, notification, archive movement, and obsolete marking
  when the protocol requires consent.
- Do not archive without passing tests and current or prior declarative user
  approval.
- Do not claim completion before the relevant checks run.
- Treat `scv/archive/` as immutable except for the lifecycle metadata operations
  explicitly allowed by the core protocol.

## Cross-action handoffs

Do not invoke an SCV skill as a shell command. When a protocol hands off to
another action:

- continue by reading that action's vendored protocol when the user already
  authorized the complete workflow; or
- give the exact optional selector, such as `$scv:work`, when a fresh decision
  or session is required.
