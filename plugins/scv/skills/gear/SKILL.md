---
name: gear
description: "Run, list, check or make gears — the project's own reusable work units in scv/gears/: tiny scripts (teeth) joined by a flow line, with one judgment step for the model. Use when the user asks to run or list a gear, wants repeated work turned into a gear, or invokes $scv:gear."
---

# SCV Gear

1. Read `../../references/codex-runtime.md` completely and apply it.
2. Read `../../vendor/scv-core/core/protocols/gear.md` completely.
3. Run the gear protocol with the safely parsed arguments: nothing or `list`, `check`, `run <name>`, `new <name> …`, or
   a plain request to make a gear.
4. On exit 10 do only the step the printed text describes and hand back only its result. On exit 11 run nothing: this
   host records no confirmation, so tell the user the step needs them to run it themselves.
5. Never write a gear or a tooth outside `scv/gears/`, and never edit `scv/gears/INDEX.tsv` by hand.
