## Summary

<!-- What & why, in 1–3 lines. -->

## Changes

-

## Tests

- [ ] `bash plugins/scv/tests/test-codex-plugin.sh` green
- [ ] `bash plugins/scv/tests/run-dry.sh` green
- [ ] relevant `plugins/scv/tests/test-*.sh` green
- [ ] relevant scenario / regression updated

## Deck (only if `$scv:deck` / `plugins/scv/DeckUI` touched)

- [ ] `pnpm -C plugins/scv/DeckUI typecheck` + `build:deck` green

## Checklist

- [ ] Follows the branch flow (`feat|fix|docs|chore|refactor|test/*` → `develop`) — see [`.github/BRANCHING.md`](./BRANCHING.md)
- [ ] No secrets / customer data
- [ ] Docs (README / skill protocol) updated if user-facing
