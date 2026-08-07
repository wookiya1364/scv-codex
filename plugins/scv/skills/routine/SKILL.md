---
name: routine
description: "List or run one maintenance routine defined under scv/routines/, or lint a routine file. Use when the user asks for a recurring maintenance task or invokes $scv:routine."
---

# SCV Routine

1. Read `../../references/codex-runtime.md` completely and apply it.
2. Read `../../vendor/scv-core/core/protocols/routine.md` completely.
3. Run the routine protocol with the safely parsed arguments: `--list`, one
   routine `<name>`, or `--lint <file>`. A single bare argument is always a
   routine name; the helper reads a leading module target only when two or
   more arguments are present.
4. Obey the routine's guardrails and exit criteria, never write to a permanent
   branch, and never register any schedule — relay the helper's host
   scheduling guidance as text only.
