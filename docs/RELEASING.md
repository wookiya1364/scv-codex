# Releasing the Codex wrapper

Three commands. Do not promote or tag by hand — the promote workflow is what
keeps every release identical.

## The procedure

`<version>` below is whatever you are releasing — `0.27.0-codex.2`,
`0.28.0-codex.1`, `1.0.0-codex.1`. Substitute it in all three commands. Nothing
here is fixed to a particular number.

```bash
VERSION=<version>       # e.g. VERSION=0.28.0-codex.1

# 1. Bump the wrapper version. This touches VERSION, plugins/scv/VERSION, and
#    plugins/scv/.codex-plugin/plugin.json at once.
bash tools/set-wrapper-version.sh "$VERSION"

# 2. Add the CHANGELOG entry and docs/releases/$VERSION.md, then open a
#    pull request into `develop` and merge it. Its title needs
#    [no-plan: <reason>] — see below.

# 3. Promote, tag, and publish.
gh workflow run promote.yml -f notes_file="docs/releases/$VERSION.md"
```

That is the whole thing. Step 3 opens `develop → stage` and `stage → main` as
pull requests, waits for each to become mergeable, merges them, tags `main` from
`VERSION`, and publishes the GitHub release.

## The version number

The wrapper version is `X.Y.Z-codex.N`, so the tag is `vX.Y.Z-codex.N`. That is
the only shape `set-wrapper-version.sh` accepts.

`X.Y.Z` is this wrapper's own number, not a copy of Core's. Merging a Core pin
does not move it — bumping it is always a separate, deliberate change. In
practice it has matched the Core feature release the wrapper picks up since
`0.21.0-codex.1`, but the two are not locked together: `0.25.0-codex.1` pinned
Core `0.25.1`, and `0.20.4-codex.1` pinned Core `0.20.5`.

`N` restarts at 1 whenever `X.Y.Z` moves, and increments for every further
release on the same `X.Y.Z`. Both kinds of release use it:

- `0.25.0-codex.2` — a wrapper-only fix. The guard shipped inert in
  `0.25.0-codex.1` and had to be made to work. Core stayed at `0.25.1`.
- `0.20.4-codex.2` — a Core patch pin, moving Core `0.20.5` → `0.20.6` without
  moving the wrapper's own feature number.

## The release pull request needs `[no-plan: <reason>]`

`check-provenance.sh` runs on every pull request into `develop` and refuses one
that changes code without adding an archived plan under
`scv/archive/<slug>/PLAN.md`. A version bump counts as code — the root `VERSION`
is not on the gate's exempt list — and this repository has no `scv/` workspace,
so there is no plan here to archive. The plan the release ships lives in
scv-core.

So declare it in the title. `0.27.0-codex.1` went in as:

```text
chore: release 0.27.0-codex.1 — Core 0.27.0, promote wait and vendor gate [no-plan: a release commit bumps VERSION and adds release notes; the plan it ships is archived in scv-core]
```

The bracket has to hold a reason. A bare `[no-plan]` is refused — the reason is
the point of the marker.

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
one first, then bump the wrapper version in a **separate** pull request.

Do not vendor Core by hand. It is tempting during a release — the version bump is
already open in front of you and copying the tree into that same branch looks
like it saves a round trip. It does not. The bot's pull request then arrives
already satisfied and gets closed as redundant, which is how both `0.25.0` and
`0.26.0` went here. And the two paths are not the same work: the bot resolves the
published release artifact and records the canonical *and* the materialized hash
in `core.lock.json`, while a hand copy records whatever the working tree held at
the time. Afterwards nothing tells them apart.

`check-vendor-provenance.sh` enforces this at merge time, from the same
`branch-flow.yml` job as the provenance gate. It denies any pull request that
rewrites `vendor/scv-core/` unless the head branch is the bot's `chore/core-*`,
the pull request is part of the release chain (`stage` or `main` as its base), or
the title carries `[manual-vendor: <reason>]` — the same shape as
`[no-plan: <reason>]`, and just as strict about the reason.

Hand-vendoring stays available, because a Core contract change can genuinely
outrun the bot. It just has to be declared.

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
the two pull requests, or that pull request never became mergeable within fifteen
minutes. Either way it is still open and nothing is left half-promoted; fix the
branch and run the workflow again. It reuses the open pull request rather than
opening a second one.

The step waits on GitHub's own `mergeStateStatus`, not on a count of checks.
Counting was wrong: a matrix job that a path filter skips is reported under its
unexpanded name before the real jobs exist, so the count reached one immediately
and the merge was attempted against required checks that had not started. That
cost two hand-merges in the `0.26.0` promotion. Three facts now have to hold at
once — nothing failed, nothing is still running, and GitHub no longer calls the
pull request `BLOCKED`.

**The workflow ran the old logic** — see "The one thing that needs two runs"
above.

**"Tag main and publish the release"** — promotion already succeeded, so `main`
carries the new `VERSION` and only the tag is missing. Fix the cause and run
again; the promotion steps will find nothing to do and skip straight to tagging.
