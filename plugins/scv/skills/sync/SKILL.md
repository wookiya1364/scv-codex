---
name: sync
description: "Preview and sync SCV templates with merge-policy and marker preservation, then detect drift between active plans, tests, and code. Use when SCV templates or plans may be stale or the user invokes $scv:sync."
---

# SCV Sync

1. Read `../../references/codex-runtime.md` completely and apply it.
2. Read `../../vendor/scv-core/core/protocols/sync.md` completely.
3. Invoke `../../adapter/scripts/sync.sh` for both preview and apply; do not
   call the core sync helper directly.
4. Run `--dry-run` before any template or state-index mutation.
5. Keep archives immutable and obtain a per-slug decision before applying a
   drift repair.
