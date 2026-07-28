# $scv:update

Check the installed SCV Codex plugin version against the latest GitHub release
and guide a marketplace refresh. This workflow is read-only.

## Language

Use project `.env` `SCV_LANG`, then the user's latest message language, then
English. Keep command names, versions, and paths unchanged.

## Protocol

### Step 1 — Run the diagnostic

```bash
bash "${SCV_PLUGIN_ROOT}/scripts/update.sh"
```

Parse:

- `INSTALLED_VERSION`
- `MARKETPLACE_NAME`
- `PLUGIN_NAME`
- `LATEST_VERSION`
- `UP_TO_DATE`

### Step 2 — Report

| `UP_TO_DATE` | Action |
|---|---|
| `yes` | Report the installed version and stop. |
| `no` | Report installed → latest, then show Step 3. |
| `unknown` | Surface the exact diagnostic reason. Ask whether the user still wants the manual refresh commands. |

### Step 3 — Guide the Codex refresh

Substitute the parsed names:

```bash
codex plugin marketplace upgrade <MARKETPLACE_NAME>
codex plugin add <PLUGIN_NAME>@<MARKETPLACE_NAME>
```

Do not run these commands automatically. They change Codex's installed plugin
state and require explicit user authorization.

After reinstalling, tell the user to start a new Codex chat or CLI session.
Installed skills and plugin tools are loaded at the new-session boundary.

### Step 4 — Project template sync

Updating the plugin does not modify the current project's `scv/` directory.
Recommend `$scv:sync` separately when the user wants the newer template merged
into the project.

## Never

- Modify project files from this workflow.
- Claim an update succeeded before the user reports the marketplace commands
  completed or a fresh session verifies the version.
- Hide release lookup or authentication failures.

