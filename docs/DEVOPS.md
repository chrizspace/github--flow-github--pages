# DevOps: branching, versioning and deploys

This repository implements the branching/versioning strategy where **no one
ever types a version number**. The version is computed from git tags plus
GitHub Issues state, and the only manual action in the pipeline is one button
click to promote a release candidate to production.

## Branches

| Branch | Origin | Purpose | Merges into | Merge strategy |
|---|---|---|---|---|
| `prod` | `release` or `hotfix/*` | Production, all users | — | merge commit |
| `release` | `dev` | UAT / beta | `prod` | merge commit |
| `dev` | — | Stable collaboration branch, **repository default** | `release` | — |
| `feature/<issue>-desc` | `dev` | New functionality | `dev` | squash |
| `fix/<issue>-desc` | `dev` | Non-critical fixes | `dev` | squash |
| `hotfix/<issue>-desc` | `prod` | Urgent production fixes | `prod`, backported to `release` and `dev` | merge commit |

`dev` is the default branch on purpose: GitHub only auto-closes an issue when
the PR merges into the default branch, and issue closure is what drives the
version bump.

## Versioning

| Event | Bump | Example |
|---|---|---|
| `feature`/`fix` issue closed as completed (landed on `dev`) | PATCH +1 | `1.7.2` → `1.7.3` |
| `type:hotfix` issue closed as completed (landed on `prod`) | PATCH +1 | `1.7.3` → `1.7.4` |
| Regular milestone closed | MINOR +1, PATCH → 0 | `1.7.4` → `1.8.0` |
| Milestone titled `Major: ...` closed | MAJOR +1, MINOR/PATCH → 0 | `1.8.0` → `2.0.0` |
| Release candidate on `release` | computed version + `-rc.n` | `1.8.0-rc.1` |

There is no `VERSION` file. `.github/actions/compute-version` re-derives the
number on every run:

1. newest `vX.Y.0` tag (created by a milestone closure) — or `v0.0.0`;
2. count of issues closed with `state_reason: completed` since that tag's date;
3. `version = X.Y.<count>` (or a MINOR/MAJOR bump for milestone runs).

Backport PRs close no issue, so they produce no `issues.closed` event and
therefore never bump anything. No exclusion label is needed.

## Workflows

| File | Trigger | Does |
|---|---|---|
| `ci.yml` | `pull_request` | Lint/build/test **and** fails the PR if it closes no issue, or if a linked issue has no milestone. Also validates branch naming. |
| `dev-integration.yml` | `issues.closed` (completed, not `type:hotfix`) | Resolves the merged PR's commit, bumps PATCH, tags, deploys Cloudflare Pages `dev`. Silent. |
| `hotfix.yml` | `issues.closed` (completed, `type:hotfix`) | Same, but deploys `prod` and opens backport PRs to `release`/`dev`. Silent. |
| `milestone-release.yml` | `milestone.closed` | MINOR/MAJOR bump, merges `dev → release`, tags `-rc.n`, deploys UAT, drafts categorized notes from the milestone's issues. |
| `promote-to-prod.yml` | `workflow_dispatch` | **The one manual step.** Finalizes the RC tag, merges `release → prod`, publishes the GitHub Release, deploys production. |
| `labels.yml` | push to `.github/labels.yml` | Keeps the label taxonomy in sync. |

All of them call the shared composite actions in `.github/actions/`.

## Guards

- Only `state_reason == completed` bumps a version, so "close as not planned"
  is ignored.
- `resolve-closing-pr` fails if an issue was closed as completed with no merged
  PR, and resolves the exact merge commit rather than trusting branch tips.
- `promote-to-prod` refuses to run when the RC's checks are failing, or when
  the final tag already exists.

## Cloudflare Pages

One project, branch deployments:

- production branch = `prod` → the real custom domain;
- `dev` and `release` deploy as previews → `dev.<project>.pages.dev`,
  `release.<project>.pages.dev`.

Because Cloudflare shares one set of Preview environment variables across all
non-production branches, read `CF_PAGES_BRANCH` at runtime if Dev and UAT ever
need different config — do not try to split it in the dashboard.

**Turn off Cloudflare's own "deploy on push" Git integration**, otherwise it
will build outside the milestone/manual-gate timing this pipeline is built on.

## Required manual setup

Run `./scripts/setup-repo.sh` for branches, default branch, protection and
labels. Then, in the GitHub UI:

1. **Settings → Environments**: create `dev`, `uat`, `production`.
   Add **required reviewers** to `production` — that list decides who may click
   *Promote to prod*.
2. **Secrets** per environment: `CLOUDFLARE_API_TOKEN` (Pages:Edit) and
   `CLOUDFLARE_ACCOUNT_ID`. The production token must not be visible to `dev`.
3. Optional repository **variable** `CLOUDFLARE_PROJECT_NAME` (defaults to the
   repository name).
4. Create the Cloudflare Pages project and attach the production domain to the
   production environment only.

Until the Cloudflare secrets exist, deploy steps log a warning and skip — the
rest of the version pipeline still runs, so you can test it immediately.

## Testing the pipeline by hand

1. Create a milestone `Sprint 1`.
2. File an issue from the **Feature** template, assign it to `Sprint 1`.
3. Create a branch from the issue page (`feature/<n>-...`), push a change,
   open a PR into `dev` with `Closes #<n>`, squash merge.
   → `dev-integration.yml` tags `v0.0.1` and deploys Dev.
4. Repeat once → `v0.0.2`.
5. Close the milestone → `milestone-release.yml` tags `v0.1.0-rc.1`, merges
   `dev → release`, deploys UAT, drafts the notes.
6. Run **Promote to prod** → `v0.1.0` published and deployed.
7. For MAJOR, repeat with a milestone titled `Major: v1.0`.

The status page at each environment shows the VERSION, GITHUB TAG, COMMIT and
BRANCH it was built from, so each step is visible without reading logs.
