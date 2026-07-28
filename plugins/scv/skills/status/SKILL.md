---
name: status
description: "Show SCV raw-material changes, active promote plans, archives, epic progress, attachments, and workspace handoffs. Use when the user asks for SCV progress or invokes $scv:status."
---

# SCV Status

1. Read `../../references/codex-runtime.md` completely and apply it.
2. Read `../../vendor/scv-core/core/protocols/status.md` completely.
3. Run the status protocol with the safely parsed arguments.
4. Preserve the helper's status categories and recommend no mutation unless the
   user explicitly requests `--ack`.
