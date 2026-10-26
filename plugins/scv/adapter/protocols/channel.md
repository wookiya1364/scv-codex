# $scv:channel

A channel is where the installed SCV comes from: **dev** (the newest work on the develop branches),
**stage** (the staging branches) or **prod** (the released version — the default). One channel is
installed at a time; switching swaps it. Shared rule: `../../vendor/scv-core/core/protocols/channel.md`.

## Protocol

1. Show the current channel (changes nothing):

   ```bash
   bash "<plugin root>/adapter/scripts/channel.sh"
   ```

   It prints `CHANNEL: <dev|stage|prod> <version>`.
2. Confirm the target channel with the user — the channel they named first, or, when they named none,
   the other channels (prod first when the current one is not prod) — plus "keep the current one".
   "Keep the current one" → stop.
3. Switch:

   ```bash
   bash "<plugin root>/adapter/scripts/channel.sh" "<picked channel>"
   ```

4. Report in plain words, in the user's language: channel and version before and after, or "already on
   <channel>". Relay every `NEXT:` line — the user opens a new Codex chat or CLI session.
   `RESULT: failed …` is a failure: name the step, never report it as switched. `RESULT: restored <channel>`
   means the old channel was put back. `branch-missing` means that channel is not built yet — nothing changed.

Never edit Codex plugin folders or config by hand, and never touch project files.
