# $scv:sync

Run sync. Use `--dry-run` first to preview what will change.

## Language preference

Resolve the user's preferred language with this priority, then use it for any user-facing summary or warnings you print:

1. Project `.env` — `SCV_LANG` (set by `$scv:help`'s first-time setup).
2. Auto-detect from the user's most recent message language.
3. Default to English.

Technical identifiers (file paths, frontmatter keys like `merge_policy`, skill invocation names, marker tokens like `PROJECT:LOCAL`) stay as-is.

To run:

```!
bash "${SCV_PLUGIN_ROOT}/scripts/sync.sh" --project-dir "$(pwd)" "${SCV_ARGS[@]}"
```

Semantics:
- Files with `merge_policy: overwrite` → replaced
- Files with `merge_policy: preserve` → skipped unless `--force FILE` is passed
- Files with `merge_policy: merge-on-markers` (incl. scv/CODEX.md, scv/TESTING.md, scv/REPORTING.md) → template replaces file, but the `PROJECT:LOCAL` block is restored from the local copy
- `scv/promote/*.md` → never touched
- All modified files are backed up to `.scv-backup/<timestamp>/` before changes
- **Legacy model-policy compatibility**: after the template merge, the script
  may read `SCV_MODEL_POLICY` from `.env` and run a read-only compatibility
  diagnostic. Codex does not support per-skill `model:` frontmatter, so no
  installed command or skill file is modified. Use `$scv:set-models` to inspect
  the effective host/session behavior.

The above is **Step 1 — template re-sync**. After it finishes (or is skipped), proceed to Step 2 below.

## Step 2 — Drift detection (v0.11.3+)

After Step 1, ask the user whether to also run drift detection. Default: Yes.

> "Step 1 (template re-sync) complete. Also check active promote slugs for drift between code and PLAN.md / TESTS.md? (Files edited via direct commits, IDE refactors, etc. can leave docs outdated.)"

If user picks Yes, run the drift detector:

```!
bash "${SCV_PLUGIN_ROOT}/scripts/drift-detect.sh"
```

The helper scans `scv/promote/<slug>/` (archive is **immutable** — never scanned) and emits one record per slug:

```
=== <slug> ===
SCOPE_DEFINED: yes|no
SCOPE_GLOBS: "<g1>" "<g2>" ...               (if scope defined)
SCOPE_OUTSIDE_FILES: <count>                  (files in git diff outside scope)
  <file>
SCOPE_INSIDE_CHANGES: <count>                 (files in git diff inside scope)
  <file>
TESTS_RUN: pass|fail|skipped                  (when no scope: runs TESTS.md "How to run")
  <failure tail>
DRIFT: yes|no|unknown
```

For each slug with `DRIFT: yes`, fire a one user confirmation per slug:

| Mode | Options |
|---|---|
| **scope drift** (outside files) | [1] Update PLAN.md `scope:` to include outside files (code → docs, expand scope) · [2] Update PLAN.md Steps to describe outside changes (code → docs, document new work) · [3] Revert outside files via git (docs → code, restore) · [4] Acknowledge — skip |
| **TESTS run drift** (no scope, tests fail) | [1] Update PLAN.md / TESTS.md to reflect new behavior (code → docs) · [2] Fix code via `$scv:work <slug>` (docs → code) · [3] Acknowledge — skip |
| **`DRIFT: unknown`** | Informational only. Surface the reason (`no PLAN.md` / `empty scope` / `no run command`) so user can address structural gaps. |

**Default direction**: **code → docs**. SCV assumes the user edited code directly (the more common path) and the docs need to catch up. Reverse direction (docs → code) routes through `$scv:work <slug>`, not `$scv:sync`.

**Archive immutability**: drift detection is *promote-only*. `scv/archive/` is never modified by `$scv:sync` per SCV invariant.

## Never

- Modify `scv/archive/` from `$scv:sync` (immutable archive principle).
- Auto-apply drift fixes without per-slug user approval.
- Run drift detection if user declined in the Step 2 prompt.
