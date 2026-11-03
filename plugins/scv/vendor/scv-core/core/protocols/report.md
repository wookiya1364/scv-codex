# $scv:report

Use the arguments attached to the current action invocation as data. Preserve them as separately quoted `SCV_ARGS` elements and pass them without `eval`; never rebuild an argument string.

Run the reporter for the given phase and status. `phase-name` should be quoted if it contains spaces. `status` is one of `passed`, `failed`, `info`.

## Language preference

Resolve the user's preferred language with this priority, then use it for any user-facing summary you print after the script runs:

1. `scv/scv_settings.json` — `SCV_LANG` (set by `$scv:help`'s first-time setup).
2. Auto-detect from the user's most recent message language.
3. Default to English.

Technical identifiers (skill invocation names, env var names like `NOTIFIER_PROVIDER`, file paths, statuses `passed`/`failed`/`info`) stay as-is.

```!
bash "${SCV_CORE_ROOT}/scripts/report.sh" "${SCV_ARGS[@]}"
```

On success prints `OK <thread_ref>` (Slack `ts` or Discord message id). On failure prints `ERROR <reason>` and exits non-zero.

After calling this, continue your Ralph iteration. Do not call Slack/Discord APIs directly from the loop — always go through this command so REPORTING.md and the settings files remain the single source of truth.

## Plain language first

Skip this section only when `scv/scv_settings.json` sets `SCV_PLAIN_LANGUAGE=off`
(absent or any other value = on). The per-turn hook carries the answer shape; its body is
`contracts/writing.md` 1–4: a **bold topic** line, then bullets with the result first; a prose
paragraph holds 1–2 sentences at most (`SCV_PLAIN_MAX_SENTENCES`).
No code values before the user asks — identifiers the user acts on
stay exact, after the plain summary. Bad: a paragraph of paths. Good: **Topic** / - the result.
This governs everything the user reads.

## Report shape

The report is read on a phone: shape it per `core/contracts/writing.md` — conclusion first,
short table cells, numbers only on what the user may point back to, an owner on every open item.

## Recording

Turns are recorded per `core/contracts/recording.md`.

## Attachment scope (v0.32.0+)

Attachments follow the plan, not the folder. By default the report uploads only
the latest test-results file that belongs to one plan: pass `--slug <slug>` to
name it; without it the helper uses the single active promote plan, and when
there is none or several it falls back to the latest file of any slug and says
so on stderr. `scv/scv_settings.json` `SCV_ATTACHMENTS_SCOPE=all` restores the old
everything-in-test-results behaviour for the whole project.

```!
bash "${SCV_CORE_ROOT}/scripts/report.sh" "<phase>" <status> --slug <slug>
```
