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

## Journal hook seam (Core 0.22.0+)

Core 0.22.0 ships two hook templates
(`vendor/scv-core/core/template/hooks/on-user-prompt.sh` and `on-stop.sh`)
that capture free conversation into the committed team journal
`scv/journal/`. Hook registration is wrapper/host-owned; this plugin
intentionally declares no `hooks` manifest entry, and the Codex plugin
surface does not deliver prompt text or a JSONL transcript path to
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
