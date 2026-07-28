---
name: sync
description: "Preview and sync SCV templates with merge-policy and marker preservation, then detect drift between active plans, tests, and code. Use when SCV templates or plans may be stale or the user invokes $scv:sync."
---

# SCV Sync

1. Read `../../references/codex-runtime.md` completely and apply it.
2. Read `../../references/protocols/sync.md` completely.
3. Run `--dry-run` before any template mutation.
4. Keep archives immutable and obtain a per-slug decision before applying a
   drift repair.

