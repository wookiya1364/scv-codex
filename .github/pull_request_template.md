## Summary

<!-- What & why, in 1–3 lines. -->

## Changes

-

## Tests

- [ ] `bash tools/verify-core.sh` green
- [ ] `bash plugins/scv/tests/test-codex-plugin.sh` green
- [ ] `bash plugins/scv/vendor/scv-core/core/tests/run-dry.sh` green
- [ ] relevant wrapper and vendored-core `test-*.sh` green
- [ ] relevant scenario / regression updated

## Deck (only if `$scv:deck` / vendored `core/DeckUI` touched)

- [ ] `pnpm -C plugins/scv/vendor/scv-core/core/DeckUI typecheck` + `build:deck` green

## Checklist

- [ ] Follows the branch flow (`feat|fix|docs|chore|refactor|test/*` → `develop`) — see [`.github/BRANCHING.md`](./BRANCHING.md)
- [ ] Code change declares `[no-plan: <reason>]` in the title (this repo has no `scv/` workspace, so the plan lives in scv-core) — an empty `[no-plan]` is refused
- [ ] `plugins/scv/vendor/scv-core/` untouched, or the title declares `[manual-vendor: <reason>]` — an empty `[manual-vendor]` is refused
- [ ] No secrets / customer data
- [ ] Docs (README / skill protocol) updated if user-facing
