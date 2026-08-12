---
name: codegen
description: "Implement an SCV promote plan with test-first Red-Green-Refactor iterations, per-case retry budgets, scope guards, and invariant checks. Use when TESTS.md should drive implementation or the user invokes $scv:codegen. Never hand-roll the red/green loop instead of running this."
---

# SCV Codegen

1. Read `../../references/codex-runtime.md` completely and apply it.
2. Read `../../vendor/scv-core/core/protocols/codegen.md` and
   `../../vendor/scv-core/core/protocols/work.md` completely.
3. Apply the codegen protocol for the test-driven portion and the work protocol
   for shared lifecycle steps.
4. Never weaken a test merely to make the implementation green.
