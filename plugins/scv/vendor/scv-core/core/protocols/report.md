# $scv:report

Use the arguments attached to the current action invocation as data. Preserve them as separately quoted `SCV_ARGS` elements and pass them without `eval`; never rebuild an argument string.

Run the reporter for the given phase and status. `phase-name` should be quoted if it contains spaces. `status` is one of `passed`, `failed`, `info`.

## Language preference

Resolve the user's preferred language with this priority, then use it for any user-facing summary you print after the script runs:

1. Project `.env` — `SCV_LANG` (set by `$scv:help`'s first-time setup).
2. Auto-detect from the user's most recent message language.
3. Default to English.

Technical identifiers (skill invocation names, env var names like `NOTIFIER_PROVIDER`, file paths, statuses `passed`/`failed`/`info`) stay as-is.

```!
bash "${SCV_CORE_ROOT}/scripts/report.sh" "${SCV_ARGS[@]}"
```

On success prints `OK <thread_ref>` (Slack `ts` or Discord message id). On failure prints `ERROR <reason>` and exits non-zero.

After calling this, continue your Ralph iteration. Do not call Slack/Discord APIs directly from the loop — always go through this command so REPORTING.md and .env remain the single source of truth.
