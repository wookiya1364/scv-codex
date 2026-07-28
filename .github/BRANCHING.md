# Branch flow

Permanent branches: **`main`** · **`stage`** · **`develop`**. They are protected
(PR required, no direct push / no deletion / no force-push) via a GitHub ruleset
(`protect-permanent-branches`) plus the `branch-flow` workflow.

## Allowed merges (enforced by `plugins/scv/scripts/check-branch-flow.sh`)

| Target | Allowed sources |
|---|---|
| `develop` | `feat/*` · `fix/*` · `docs/*` · `chore/*` · `refactor/*` · `test/*` |
| `stage`   | `develop` |
| `main`    | `stage` · `fix/*` (hotfix) |

## Flow

1. Branch off `develop` (e.g. `feat/<slug>`), open a PR **→ `develop`**.
2. Promote `develop` → `stage` → `main` via PR.

Merged head branches are auto-deleted (repo setting `delete_branch_on_merge`).

> This file is the branch-strategy reference used by the
> `plugins/scv/scripts/check-branch-flow.sh` check and the `branch-flow`
> GitHub Actions workflow.
