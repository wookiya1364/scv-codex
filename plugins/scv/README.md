<div align="center">

<img src="vendor/scv-core/core/assets/scv-circle.png" width="128" height="128" alt="SCV mascot" />

# SCV for Codex

**Standard · Cowork · Verify**

Every change ships with a plan and tests — and the tests run forever.

[Repository guide](../../README.md) ·
[한국어](./README.ko.md) · [日本語](./README.ja.md)

</div>

## Install

```bash
codex plugin marketplace add https://github.com/wookiya1364/scv-codex.git
codex plugin add scv@scv-codex
```

Start a new Codex session, then **just talk**:

```text
Use SCV — I want to add a refund button to checkout.
```

SCV joins free conversation by default (`SCV_ALWAYS_ON` in
`scv/scv_settings.json`; `off` = explicit skills only). `$scv:help` is the
explicit selector; the full skill table, settings, guardrails, and multi-repo
guide live in the [repository guide](../../README.md).

## What's in the box

- The loop: materials → plan + tests → implement → archive → accumulating
  regression. `PLAN.md` is the single source; evidence attaches to the PR/MR.
- Settings in `scv/scv_settings.json` (auto-created, every key documented) +
  a git-ignored secret file. `.env` is never read.
- A blocking `PreToolUse` guard (hand-made plan files, writes outside `scv/`)
  that lifts once any SCV action runs — fails open, inert without `scv/`,
  `SCV_GUARD=off` disables. Codex hooks are not hot-reloaded: restart Codex
  after updating and re-approve via `/hooks`. Contract:
  [`core/contracts/guard.md`](vendor/scv-core/core/contracts/guard.md).
- A pinned, checksummed [scv-core](https://github.com/wookiya1364/scv-core)
  payload under `vendor/scv-core/` — nothing fetched at runtime.

To update: `codex plugin marketplace upgrade scv-codex` →
`codex plugin add scv@scv-codex` → new session. The project's templates then
refresh themselves on the first action of that session — and say so.

MIT © [wookiya1364](https://github.com/wookiya1364)
