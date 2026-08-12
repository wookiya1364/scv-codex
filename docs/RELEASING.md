# Releasing the Codex wrapper

Three commands. Do not promote or tag by hand — the promote workflow is what
keeps every release identical.

## The procedure

`<version>` below is whatever you are releasing — `0.25.0-codex.1`,
`0.25.0-codex.2`, `1.0.0-codex.1`. Substitute it in all three commands. Nothing
here is fixed to a particular number.

```bash
VERSION=<version>       # e.g. VERSION=0.25.0-codex.1

# 1. Bump the wrapper version. This touches VERSION, plugins/scv/VERSION, and
#    plugins/scv/.codex-plugin/plugin.json at once.
bash tools/set-wrapper-version.sh "$VERSION"

# 2. Add the CHANGELOG entry and docs/releases/$VERSION.md, then open a
#    pull request into `develop` and merge it.

# 3. Promote, tag, and publish.
gh workflow run promote.yml -f notes_file="docs/releases/$VERSION.md"
```

That is the whole thing. Step 3 opens `develop → stage` and `stage → main` as
pull requests, waits for their checks, merges them, tags `main` from `VERSION`,
and publishes the GitHub release.

The wrapper version is `X.Y.Z-codex.N`, so the tag is `vX.Y.Z-codex.N`. The
`X.Y.Z` part tracks the Core release this wrapper pins; `N` counts wrapper-only
releases against the same Core.

## Why not by hand

The workflow never pushes to a permanent branch — the branch ruleset requires a
pull request for `develop`, `stage`, and `main`, so it opens them and merges.
`workflow_dispatch` is its only trigger, which means starting it is the human
gate: nothing promotes on a schedule or on push.

A red check stops the chain and leaves that pull request open. A failed
promotion is a pull request you can read, not a half-finished merge.

## Core versions are not yours to bump

`plugins/scv/vendor/scv-core/**` is a materialized Core release. Never edit it
directly, and never bump the versions inside it. A new Core pin arrives as an
automatic `chore/core-<version>` pull request from `core-sync.yml`; merge that
first, then release the wrapper.

## The one thing that needs two runs

`workflow_dispatch` always executes the copy of the workflow file on the default
branch. So when the change you are promoting **edits `promote.yml` itself**, the
first run still uses the old file: it promotes your fix to `main` and may fail on
whatever the fix addresses. Run it a second time and the corrected file executes.

This applies only to changes that touch the workflow file. Every other release is
one run.

## Options

```bash
gh workflow run promote.yml                       # promote, tag, release
gh workflow run promote.yml -f release=false      # promote only, no tag
gh workflow run promote.yml \
  -f notes_file=docs/releases/<version>.md        # hand-written notes
```

The tag always comes from whatever `VERSION` holds on `main` — the workflow takes
no version argument, so there is nothing to keep in sync by hand.

Without `notes_file` the release notes are generated from the commits.

## When it fails

Read which step failed.

**"Promote develop to stage, then stage to main"** — a check went red on one of
the two pull requests. It is still open; fix the branch and run the workflow
again. It reuses the open pull request rather than opening a second one.

**"Tag main and publish the release"** — promotion already succeeded, so `main`
carries the new `VERSION` and only the tag is missing. Fix the cause and run
again; the promotion steps will find nothing to do and skip straight to tagging.
