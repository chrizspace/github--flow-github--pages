<!--
  Every feature/fix/hotfix PR must close an issue that has a milestone.
  CI enforces both. Backport PRs (label: backport) are exempt — and must NOT
  contain a closing keyword, or they would bump the version a second time.
-->

## What and why

<!-- One or two sentences. -->

Closes #

## Type

- [ ] Feature (`feature/<issue>-desc` → `dev`, squash merge)
- [ ] Fix (`fix/<issue>-desc` → `dev`, squash merge)
- [ ] Hotfix (`hotfix/<issue>-desc` → `prod`, merge commit)
- [ ] Backport (bot-generated, closes nothing)

## Checklist

- [ ] The linked issue has a milestone assigned
- [ ] Branch name follows `<type>/<issue-number>-short-description`
- [ ] Rebased on the target branch
- [ ] CI is green

## Versioning

No version number is set by hand. Closing the linked issue bumps PATCH
automatically; closing the milestone bumps MINOR (or MAJOR for a `Major:`
milestone). See `docs/DEVOPS.md`.
