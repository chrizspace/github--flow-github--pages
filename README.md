# github--flow-github--pages

A reference implementation of a fully automatic branching / versioning / release
pipeline, plus a sample **release status page** that shows the VERSION, GITHUB
TAG, COMMIT and BRANCH it was built from.

```
feature/* ┐
fix/*     ├─PR─▶ dev ──milestone closed──▶ release ──manual button──▶ prod
hotfix/* ─┴────────────────────────────────────────────────────────▶ prod
```

- **PATCH** bumps when an issue is closed by a merged PR (silent).
- **MINOR** bumps when a milestone is closed; **MAJOR** when its title starts
  with `Major: `.
- The version is **computed at run time** from tags + Issues — there is no
  `VERSION` file to drift or conflict.
- The only manual step in the whole pipeline is the **Promote to prod** button.

## Quick start

```bash
./scripts/setup-repo.sh     # branches, default branch, protection, labels
./build.sh                  # build the status page into dist/
python3 -m http.server -d dist 8080
```

## Docs

- [docs/DEVOPS.md](docs/DEVOPS.md) — branching model, version math, workflows,
  Cloudflare Pages setup, and how to test the pipeline by hand.
- [CONTRIBUTING.md](CONTRIBUTING.md) — issue/branch/PR conventions.

## Layout

```
.github/actions/     compute-version, resolve-closing-pr, deploy-pages
.github/workflows/   ci, dev-integration, hotfix, milestone-release, promote-to-prod, labels
src/                 the static status page
build.sh             emits dist/ + dist/version.json
scripts/setup-repo.sh
```
