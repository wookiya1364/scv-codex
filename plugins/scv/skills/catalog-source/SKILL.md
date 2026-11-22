---
name: catalog-source
description: "Switch a project to no comments in code — the pure-function catalog is the source. on moves every code comment into scv/core/catalog/pure now and bans new ones; off lifts only the ban. No argument flips it. Use when the user wants code comments gone or allowed again, or invokes $scv:catalog-source."
---

# SCV Catalog Source

1. Read `../../references/codex-runtime.md` completely and apply it.
2. Read `../../vendor/scv-core/core/protocols/catalog-source.md` completely.
3. Run the switch with the safely parsed argument — `on`, `off`, or nothing (flip).
4. Relay the state before and after; after a move, say how many files and comment lines moved and that nothing was
   committed. After `off`, say only the comment ban is lifted.
