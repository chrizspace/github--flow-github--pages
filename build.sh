#!/usr/bin/env bash
# Builds the static site into dist/ and generates dist/version.json.
#
# Every value is taken from the environment so CI can inject the computed
# version; sensible git-derived defaults are used for local builds.
set -euo pipefail

cd "$(dirname "$0")"

OUT_DIR="${OUT_DIR:-dist}"

git_or() {
  # $1 = git command output fallback chain
  "$@" 2>/dev/null || true
}

COMMIT="${COMMIT:-$(git_or git rev-parse HEAD)}"
BRANCH="${BRANCH:-$(git_or git rev-parse --abbrev-ref HEAD)}"
TAG="${TAG:-$(git_or git describe --tags --exact-match)}"
VERSION="${VERSION:-${TAG#v}}"
ENVIRONMENT="${ENVIRONMENT:-local}"
REPOSITORY="${REPOSITORY:-$(git_or git config --get remote.origin.url)}"
BUILT_AT="${BUILT_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

# Normalise a git remote URL down to owner/repo.
REPOSITORY="$(printf '%s' "$REPOSITORY" | sed -E 's#^git@github\.com:##; s#^https://github\.com/##; s#\.git$##')"

: "${VERSION:=0.0.0-dev}"
: "${COMMIT:=unknown}"
: "${BRANCH:=unknown}"
: "${TAG:=none}"
: "${REPOSITORY:=unknown}"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
cp src/index.html src/styles.css src/app.js "$OUT_DIR/"

cat > "$OUT_DIR/version.json" <<JSON
{
  "version": "${VERSION}",
  "tag": "${TAG}",
  "commit": "${COMMIT}",
  "branch": "${BRANCH}",
  "environment": "${ENVIRONMENT}",
  "repository": "${REPOSITORY}",
  "built_at": "${BUILT_AT}"
}
JSON

echo "Built ${OUT_DIR}/ — version ${VERSION} (${ENVIRONMENT}) @ ${COMMIT}"
