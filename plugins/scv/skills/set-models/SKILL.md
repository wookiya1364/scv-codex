---
name: set-models
description: "Inspect SCV model-policy compatibility and help configure Codex session or project model settings without mutating installed skills. Use when migrating SCV_MODEL_POLICY, choosing Codex execution quality, or invoking $scv:set-models."
---

# SCV Model Policy

1. Read `../../references/codex-runtime.md` completely and apply it.
2. Read `../../adapter/protocols/set-models.md` completely.
3. Treat Claude per-command model frontmatter as unsupported compatibility
   input. Never edit installed `SKILL.md` files to select a model.
4. Explain the effective Codex host/session model. Change project
   `.codex/config.toml` only when the user explicitly requests that durable,
   repository-wide change.
