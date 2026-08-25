<div align="center">

<img src="plugins/scv/vendor/scv-core/core/assets/scv-circle.png" width="160" height="160" alt="SCV mascot" />

# SCV for Codex

**Standard · Cowork · Verify**

**A Codex plugin for teams. Every change ships with a plan and tests — and
the tests run forever.**

[Latest release](https://github.com/wookiya1364/scv-codex/releases/latest) ·
[한국어](./README.ko.md) · [日本語](./README.ja.md)

</div>

---

## What is SCV

Talk about a change → SCV refines it into a plan with executable tests →
implements it → attaches the evidence to the PR/MR → archives the plan. Every
archived test joins a regression suite that runs against every future change.

## Install

```bash
codex plugin marketplace add https://github.com/wookiya1364/scv-codex.git
codex plugin add scv@scv-codex
```

Start a new Codex session so the installed skills load.

- **macOS**: `brew install bash` once (bash 4+). **Linux / WSL**: nothing to do.
- Recommended CLIs: `git`, `curl`, `jq`, `gh` (or `glab`).

## How you use it

**Just talk.** SCV joins the conversation by default:

```text
You:  Use SCV — I want to add a refund button to checkout.
SCV:  (enters conversation mode, asks goal / scope / acceptance,
       then offers to draft the plan and tests)
```

Describe what you want and SCV refines it into a plan; ask what to do next and
it diagnoses the repository; ask about past work and it searches the archive.
`$scv:help` is the explicit selector when you want it, and `SCV_ALWAYS_ON=off`
in `scv/scv_settings.json` restores command-only behavior. (`/scv:<name>` is
the Claude Code spelling — not used here.)

The loop behind every conversation: materials → plan + tests → implement →
archive → regression. The archive is not a graveyard — the longer the team
uses SCV, the thicker the safety net.

## What you get

| Team problem | SCV's answer |
|---|---|
| An AI diff you must run yourself before trusting | Tests run as the gate; e2e evidence attaches to the PR/MR, tracked by the actual run |
| One change described differently in ticket · PR · chat | `PLAN.md` is the single source; tickets linked via `refs:` |
| Decisions vanish with the session | `scv/DECISIONS.md` — append-only, automatic |
| Old features silently break | Every archived plan's tests re-run as one suite |

## Settings

One file: `scv/scv_settings.json` — auto-created with every key documented.
Secrets go to a separate git-ignored file. `.env` is never read or written.

| Key | Default | What it does |
|---|---|---|
| `SCV_ALWAYS_ON` | `on` | SCV joins free conversation; `off` = explicit skills only |
| `SCV_PLAIN_LANGUAGE` | `on` | plain-first answers; `off` silences |
| `SCV_LANG` | auto | `english` · `korean` · `japanese` |
| `NOTIFIER_PROVIDER` | off | `slack` or `discord` |

```bash
bash plugins/scv/vendor/scv-core/core/scripts/settings-set.sh SCV_LANG=korean
```

## Skills

Conversation routes for you; the explicit selectors:

| Skill | Does |
|---|---|
| `$scv:help` | Diagnose · refine an idea · search the archive |
| `$scv:status` | What's in flight |
| `$scv:promote` | Materials → plan + tests + diagrams |
| `$scv:work <slug>` | Implement · test · archive · PR/MR with evidence |
| `$scv:codegen <slug>` | TDD-first variant (tests drive the code) |
| `$scv:regression` | Run every archived plan's tests |
| `$scv:deck [<md>]` | Markdown → planning document / slides |
| `$scv:report` | Phase result to Slack/Discord |
| `$scv:sync` | Refresh templates + drift detection |
| `$scv:routine <name>` | One-file maintenance routines |
| `$scv:workspace` · `$scv:handoff` | Multi-repo umbrella · cross-repo declaration |
| `$scv:update` · `$scv:set-models` · `$scv:install-deps` | Update guide · model-policy diagnostic · CLI deps |

`$scv:set-models` is read-only on this host: Codex skills cannot pin per-skill
models, so it diagnoses legacy policy intent and only edits
`.codex/config.toml` after explicit request, preview, and confirmation.

## Guardrails

- **In-session**: a `PreToolUse` guard refuses hand-created plan files and
  writes outside `scv/` until a receipt exists — here minted by a shell call
  into the vendored scripts (Codex has no skill-invocation event, so this is
  deliberately weaker than the Claude Code wrapper). Fails open on internal
  error; inert where SCV isn't adopted; `SCV_GUARD=off` disables.
- **At merge**: CI gates require an archived plan for code changes
  (`[no-plan: <reason>]` declares an exception) and declared vendor rewrites
  (`[manual-vendor: <reason>]`).

Codex hooks are not hot-reloaded: restart Codex after updating the plugin, and
re-approve changed hooks via `/hooks`. Contract:
[`core/contracts/guard.md`](plugins/scv/vendor/scv-core/core/contracts/guard.md).

## Multi-repo

`$scv:workspace` creates/joins an umbrella across FE/BE/service repos;
`$scv:handoff` declares cross-repo work where the other repo will see it.
Detaching restores standalone behavior. Monorepos with per-module `scv/`
target a module by leading argument: `$scv:status FE`.

## Shared core and releases

Behavior lives in [scv-core](https://github.com/wookiya1364/scv-core),
vendored checksummed under `plugins/scv/vendor/scv-core/` — nothing fetched at
runtime. Wrapper, core, and template versions move independently; the core
lock records source and artifact hashes. A sync bot proposes pin updates as
`chore/core-*` PRs; releases walk `develop → stage → main` via
`gh workflow run promote.yml` — see [docs/RELEASING.md](docs/RELEASING.md).

## Origin and license

SCV for Codex and
[SCV for Claude Code](https://github.com/wookiya1364/scv-claude-code) are thin
host adapters over the same SCV Core.

MIT © [wookiya1364](https://github.com/wookiya1364)
