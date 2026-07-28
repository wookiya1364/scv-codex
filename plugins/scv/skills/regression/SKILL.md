---
name: regression
description: "Run accumulated TESTS.md suites from SCV archives, honor obsolete and superseded plans, and triage failures per slug. Use for regression checks, CI-style SCV verification, or $scv:regression."
---

# SCV Regression

1. Read `../../references/codex-runtime.md` completely and apply it.
2. Read `../../references/protocols/regression.md` completely.
3. Run the requested regression scope and preserve its exit-code semantics.
4. Never ask interactive questions in `--ci` mode; triage failures one slug at
   a time otherwise.

