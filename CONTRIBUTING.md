# Contributing

The short version: **every branch starts from an issue, and no one ever edits a
version number.** Full detail lives in [docs/DEVOPS.md](docs/DEVOPS.md).

## 1. File an issue first

Use one of the issue templates (Feature / Bug fix / Hotfix). Every issue must:

- have a **milestone** assigned (CI fails the PR otherwise), and
- carry its type label (`type:feature`, `type:fix`, `type:hotfix` — the
  templates apply these for you).

Name milestones normally (`Sprint 24`, `Q3 - Search`) for a MINOR release, or
prefix them `Major: ` for a MAJOR release. That title is the only release
decision anyone makes, and it is made at planning time.

Large issues (epics) get split into sub-issues in the same milestone, each with
its own short-lived branch.

## 2. Branch from the issue

Use the **Create a branch** button on the issue page so the naming and linking
are automatic:

```
feature/123-add-login
fix/124-broken-redirect
hotfix/125-checkout-500      # branches off prod, not dev
```

Rebase on the target branch before opening the PR.

## 3. Open the PR

- `feature/*` and `fix/*` → `dev`, **squash merge**.
- `hotfix/*` → `prod`, **merge commit**; backports to `release` and `dev` are
  opened automatically.
- The PR body must contain a closing keyword: `Closes #123`.
- Backport PRs must *not* contain a closing keyword — that is what keeps them
  from bumping the version a second time.

CI blocks the merge unless the PR closes an issue, that issue has a milestone,
the branch name is valid, and the build passes.

## 4. Let the automation do the versioning

| You do | Automation does |
|---|---|
| Merge the PR (issue auto-closes) | PATCH +1, tag, deploy Dev — silently |
| Close the milestone | MINOR/MAJOR bump, `dev → release`, `-rc.n` tag, UAT deploy, drafted release notes |
| Click **Promote to prod** | Final tag, GitHub Release, production deploy |

## Local development

```bash
./build.sh          # writes dist/ including dist/version.json
python3 -m http.server -d dist 8080
```

`dist/` is generated and never committed — the version is computed, not stored.
