---
name: report
description: "Report an SCV phase or regression result to the configured Slack or Discord channel with relevant artifacts. Use when the user asks to notify the team about SCV results or invokes $scv:report."
---

# SCV Report

1. Read `../../references/codex-runtime.md` completely and apply it.
2. Read `../../vendor/scv-core/core/protocols/report.md` completely.
3. Preview the destination, message, and artifacts before an external send
   unless the user already gave explicit send authorization.
4. Preserve dry-run and retry-queue behavior.
