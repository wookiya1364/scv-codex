# Codex runtime adapter

Apply this adapter before executing any SCV skill protocol. It is the
authoritative compatibility layer when a protocol still mentions Claude Code.

## Resolve paths

1. Resolve the active skill's absolute `SKILL.md` path from the skill metadata
   Codex loaded.
2. Set `SCV_PLUGIN_ROOT` to the directory two levels above that skill folder.
   For `.../skills/help/SKILL.md`, the root is `.../`.
3. Validate that both `$SCV_PLUGIN_ROOT/.codex-plugin/plugin.json` and
   `$SCV_PLUGIN_ROOT/scripts/` exist before running a helper.
4. If `PLUGIN_ROOT` or `CLAUDE_PLUGIN_ROOT` is already set and passes the same
   validation, it may be used. Never assume a source-checkout path.

Use absolute, quoted paths for all bundled helpers:

```bash
bash "$SCV_PLUGIN_ROOT/scripts/help.sh"
```

## Parse invocation arguments

- Treat the text after the explicit `$scv:<name>` mention as that skill's
  arguments.
- For implicit invocation, infer arguments only when the user's request makes
  them unambiguous.
- Build a shell array named `SCV_ARGS`; pass it as `"${SCV_ARGS[@]}"`.
- Never pass a literal `$ARGUMENTS`, concatenate untrusted input into a shell
  string, or use `eval`.
- If a required slug, phase, target, or choice is missing and cannot be
  discovered safely, ask one concise question.

## Translate legacy protocol terms

The bundled `references/protocols/*.md` files preserve the mature SCV workflow. Interpret
legacy terms as follows:

| Protocol term | Codex behavior |
|---|---|
| `/scv:name` | `$scv:name` |
| `${CLAUDE_PLUGIN_ROOT}` | validated `SCV_PLUGIN_ROOT` |
| `$ARGUMENTS` | the safely parsed `SCV_ARGS` array |
| `AskUserQuestion` | ask the user concisely; use a structured input tool only when the current surface provides one |
| `Bash`, `Read`, `Glob`, `Grep`, `Write`, `Edit` | the equivalent current Codex tools |
| `Skill(name)` | use the named skill only when it is installed; otherwise follow the protocol's fallback |
| `Claude` | Codex |
| Claude `model:` frontmatter | ignore; Codex model selection is host/session controlled |

When this adapter conflicts with a legacy protocol, this adapter wins.

## Language

Use this priority for user-facing prose:

1. Project `.env` `SCV_LANG`.
2. The language of the user's latest message.
3. English.

Treat `.claude/settings*.json` only as an optional migration fallback. Never
require it in a Codex-only project.

## Safety and completion

- Keep all filesystem changes inside the user's active project unless the user
  explicitly scopes another path.
- Preserve existing project files and unrelated worktree changes.
- Preview dependency installs, template sync, workspace detach, remote push,
  PR/MR creation, Slack/Discord notification, archive movement, and obsolete
  marking when the protocol requires user consent.
- Do not archive without passing tests plus current or prior declarative user
  approval.
- Do not claim completion before the protocol's relevant checks run.
- Treat `scv/archive/` as immutable except for the narrowly defined lifecycle
  metadata operations in the relevant protocol.

## Cross-skill handoffs

Do not attempt to invoke another skill as a shell command. When a protocol
hands off to another SCV skill, either:

- read that skill's protocol directly and continue when the user
  already authorized the full workflow; or
- tell the user the exact `$scv:<name>` invocation to run next when a new decision
  or fresh session is required.
