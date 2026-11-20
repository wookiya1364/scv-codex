---
name: ask-mode
description: "Switch when SCV asks you: ends (only at the start, the end, and before irreversible acts) or all (every decision, the default). No argument flips it. Use when the user wants SCV to stop asking mid-work, to ask everywhere again, or invokes $scv:ask-mode."
---

# SCV Ask Mode

1. Read `../../references/codex-runtime.md` completely and apply it.
2. Read `../../vendor/scv-core/core/protocols/ask-mode.md` completely.
3. Run the switch with the safely parsed argument — `ends`, `all`, or nothing (flip).
4. Relay the mode before and after; when the helper prints `ENV_VALUE:`, say the
   environment variable still decides.
