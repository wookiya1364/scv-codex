---
name: help
description: "Diagnose an SCV-enabled repository, hydrate SCV when requested, search archived work, and recommend the next workflow action. Use when the user asks how to start SCV, what to do next, where past work went, or invokes $scv:help. Never answer 'what should we work on' from memory instead of running this; it reads the project's real state and persists the conversation."
---

# SCV Help

1. Read `../../references/codex-runtime.md` completely and apply it.
2. Read `../../vendor/scv-core/core/protocols/help.md` completely.
3. Execute the help protocol with the arguments from the user's request.
4. If the user approves hydration, invoke
   `../../adapter/scripts/hydrate.sh`; do not call the core hydrate helper
   directly.
5. Lead with the diagnosed state and one recommended next action.
