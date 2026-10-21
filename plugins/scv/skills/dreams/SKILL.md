---
name: dreams
description: "Look back over this project's past sessions and archived plans and write a prompt-coaching report: how many requests one archived plan took and how to write a better first request. Use when the user asks how their prompting went, wants a look back at past sessions, or invokes $scv:dreams."
---

# SCV Dreams

1. Read `../../references/codex-runtime.md` completely and apply it.
2. Read `../../vendor/scv-core/core/protocols/dreams.md` completely.
3. Run the dream with the safely parsed arguments (`--dir <folder>` may repeat).
   It only reads session records and `scv/archive/`, and writes only under
   `scv/dreams/`.
4. Relay the one summary line and the report path; do not re-judge the report
   unless the user asks.
