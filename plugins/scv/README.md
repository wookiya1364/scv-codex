<div align="center">

<img src="vendor/scv-core/core/assets/scv-circle.png" width="128" height="128" alt="SCV mascot" />

# SCV for Codex

**Standard · Cowork · Verify**

A process-first Codex plugin that turns source material into an approved plan
and executable tests, implements the plan, and keeps every approved test in an
accumulating regression suite.

[Repository guide](../../README.md) ·
[한국어](./README.ko.md) · [日本語](./README.ja.md)

</div>

## Install

```bash
codex plugin marketplace add https://github.com/wookiya1364/scv-codex.git
codex plugin add scv@scv-codex
```

Start a new Codex chat or CLI session, then ask naturally:

```text
Use SCV to diagnose this project and tell me what to do next.
```

Codex can invoke all 15 skills from natural language. `$scv:help` is an
optional exact selector; `/scv:help` is a Claude Code slash command and is not
used here.

## Skills

| Skill | Behavior |
|---|---|
| **`$scv:help`** | Diagnose state, develop an idea, search archives, and route to the next action. |
| `$scv:status` | Summarize raw inputs, active plans, epics, workspace mode, and handoffs. |
| `$scv:promote` | Turn `scv/raw/` into PLAN, TESTS, and feature architecture. |
| `$scv:work <slug>` | Implement, test, collect evidence, request approval, archive, and prepare a PR/MR. |
| `$scv:codegen <slug>` | Experimental TESTS-driven Red → Green loop; hands completion back to `$scv:work`. |
| `$scv:deck [<md>]` | Render Markdown as a planning document or DeckUI slide deck. |
| `$scv:update` | Read-only version check and Codex marketplace refresh guide. |
| `$scv:regression` | Run test instructions from all current archive entries. |
| `$scv:routine <name>` | List, lint, or run one maintenance routine defined under `scv/routines/`; scheduling stays host-owned. |
| `$scv:report` | Report a phase result to configured Slack or Discord. |
| `$scv:sync` | Merge templates and detect drift between active plans, code scope, and tests. |
| `$scv:install-deps` | Detect CLIs and offer consent-gated installation help. |
| `$scv:workspace` | Create, join, inspect, or detach a nested umbrella workspace. |
| `$scv:handoff` | Record cross-repository work and context; push and notification require consent. |
| `$scv:set-models` | Diagnose legacy model-policy intent and explain effective Codex configuration without editing installed skills. |

## Codex compatibility

The workflow, repository layout, Bash helpers, plans, tests, archives,
regression behavior, deck generation, and multi-repository coordination come
from the pinned `vendor/scv-core` payload shared with the Claude Code wrapper.
The installed plugin is self-contained and never fetches core at runtime.

Wrapper, core, and template versions are tracked separately. The core lock
records source and payload checksums, plus the verified release artifact
SHA-256 when applicable. `scv/SCV.md` is canonical; historical `CLAUDE.md` or
`CODEX.md` state remains readable without mutation and migrates only during an
approved sync.

One host-level difference is explicit: Codex plugin skills cannot pin a
different model per skill. `$scv:set-models` is therefore a read-only migration
diagnostic for legacy `SCV_MODEL_POLICY` values. It never translates Anthropic
model names by guesswork or rewrites installed `SKILL.md` files. A durable
`.codex/config.toml` edit requires an explicit request, capability verification,
a preview, and confirmation.

## Workspace guard (0.25.0-codex.2+)

`hooks/hooks.json` registers a deliberately blocking `PreToolUse` guard. It
denies two things: hand-creating `PLAN.md`, `TESTS.md`, or
`FEATURE_ARCHITECTURE.md` under `scv/promote/<slug>/`, and writing anywhere
outside `scv/`. Editing a plan file that already exists is always allowed.
`*.md`, `.gitignore`, `.gitattributes`, `LICENSE`, and `.codex/config.toml` are
exempt; `.env` is not, because the sanctioned `.env` writes go through
`vendor/scv-core/core/scripts/env-set.sh` instead.

Both blocks lift for the rest of the session as soon as a receipt exists. Two
entries are registered here — `gate-bash` for `Bash`, `shell`, and `local_shell`,
and `gate-write` for `apply_patch`, `Write`, `Edit`, and `MultiEdit` — and there
is no separate mint entry, because Codex has no skill-invocation event to mint
from. The receipt is minted by the shell entry when a command names the vendored
`core/scripts/` directory or `adapter/scripts/` — both watched since 0.28.0
via `SCV_GUARD_SCRIPTS`'s colon list, so the adapter-routed actions mint too.
Every protocol calls one of them before it writes anything. Both commands
resolve the plugin directory from
`${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}`; there is no `CODEX_PLUGIN_ROOT`, and
naming it is what shipped the guard inert in `0.25.0-codex.1`. Because the file
sits at the plugin-root default path, `.codex-plugin/plugin.json` still declares
no `hooks` key.

The guard fails **open** — an internal error prints one line to stderr and allows
the action — and is inert in a project with no `scv/` directory. Export
`SCV_GUARD=off` to disable it entirely; it is read from the process environment
only, never from a file, so nothing in the repository can exempt itself.
`SCV_GUARD_RULE_B=off` keeps only the plan rule. The contract is
[`vendor/scv-core/core/contracts/guard.md`](vendor/scv-core/core/contracts/guard.md).

Two operational notes on Codex hooks: they are not hot-reloaded, so restart Codex
after updating the plugin, and trust is pinned to a hook's contents — a release
that changes `guard.sh` leaves you unenforced until you approve it again through
`/hooks`.

## Effort governor (Core 0.29.0+)

`$scv:work` and `$scv:codegen` judge each plan's execution band before
implementing and shape HOW the work runs to match — your session effort
setting is never touched. Set `SCV_EFFORT_MODE=auto|ask|off` in the project
`.env`; the default is `auto`, which prints one notice line and proceeds.
`off` skips the step entirely: the classifier is never invoked, nothing is
printed, and execution is exactly what it was before this feature. This host
has no subagent fan-out, so the orchestration band's verification degrades to
sequential multi-lens passes — the full band-by-stage grid is in the
[repository guide](../../README.md)'s "How the effort governor maps to this
host" section. The contract is
[`vendor/scv-core/core/protocols/work.md`](vendor/scv-core/core/protocols/work.md)
Step 5e.

## Journal hook seam (Core 0.22.0+)

Core 0.22.0 ships two hook templates
(`vendor/scv-core/core/template/hooks/on-user-prompt.sh` and `on-stop.sh`)
that capture free conversation into the committed team journal
`scv/journal/`. Hook registration is wrapper/host-owned. The guard above
ships registered, but the journal pair does not: the Codex plugin surface
does not deliver prompt text or a JSONL transcript path to
plugin-projected commands. Registration on a Codex host is therefore a
documented user action — see
[`references/journal-hooks.md`](references/journal-hooks.md) for the event
mapping, stdin JSON contract, `SCV_CORE_ROOT` export, and the non-blocking
and redaction guarantees. Where the host provides no JSONL transcript, the
turn-end registration is omitted; the seam contract allows this partial
implementation, and that gap applies to this wrapper today.

## Safety and updates

SCV requires passing tests and approval before archive. Push, PR/MR creation,
notifications, dependency installation, and persistent Codex config changes
stay consent-gated. `$scv:update` and model-policy inspection are read-only.

Deck dependencies, builds, and generated deck JSON live in an external cache
keyed by the pinned Core payload. During a maintainer update, known runtime
from the previous vendor or legacy plugin-root `DeckUI` is copied additively
from a stable snapshot; neither source is modified or deleted. The verified
Core tree is replaced under an owner lock with exact rollback on catchable
failures.

To refresh an installed copy:

```bash
codex plugin marketplace upgrade scv-codex
codex plugin add scv@scv-codex
```

Then start a new Codex session. Run `$scv:sync` separately if you also want to
merge the newer project templates.

Set `SCV_LANG=en|ko|ja` in the project `.env` for a persistent generated
language. Otherwise SCV follows the latest user message and falls back to
English.

MIT © [wookiya1364](https://github.com/wookiya1364)
