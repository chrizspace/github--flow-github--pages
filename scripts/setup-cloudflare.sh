#!/usr/bin/env bash
# Wires up Cloudflare Pages for this repository:
#   - creates the Pages project (production branch = prod) if missing
#   - disables Cloudflare's own "deploy on push" Git integration expectations
#     (nothing to disable when the project has no Git connection, which is the
#     case for a project created this way)
#   - stores CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID as GitHub environment
#     secrets on dev, uat and production
#
# Usage:
#   CLOUDFLARE_API_TOKEN=... CLOUDFLARE_ACCOUNT_ID=... ./scripts/setup-cloudflare.sh
#
# The API token needs the "Cloudflare Pages: Edit" permission. Create one at
# https://dash.cloudflare.com/profile/api-tokens
set -euo pipefail

REPO="${REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
PROJECT="${CLOUDFLARE_PROJECT_NAME:-$(gh variable list --repo "$REPO" --json name,value \
  --jq '.[] | select(.name == "CLOUDFLARE_PROJECT_NAME") | .value' 2>/dev/null || true)}"
PROJECT="${PROJECT:-$(basename "$REPO")}"
PRODUCTION_BRANCH="${PRODUCTION_BRANCH:-prod}"

: "${CLOUDFLARE_API_TOKEN:?set CLOUDFLARE_API_TOKEN (Pages:Edit)}"
: "${CLOUDFLARE_ACCOUNT_ID:?set CLOUDFLARE_ACCOUNT_ID}"

say() { printf '\n==> %s\n' "$1"; }
api() { curl -sS -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" "$@"; }

base="https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects"

say "Verifying the Cloudflare token"
if ! api "$base" | grep -q '"success":true'; then
  echo "Cloudflare rejected the token. It needs the 'Cloudflare Pages: Edit' permission on this account." >&2
  exit 1
fi
echo "  token OK"

say "Creating the Pages project '${PROJECT}'"
if api "${base}/${PROJECT}" | grep -q '"success":true'; then
  echo "  already exists"
else
  resp="$(api -X POST "$base" \
    --data "{\"name\":\"${PROJECT}\",\"production_branch\":\"${PRODUCTION_BRANCH}\"}")"
  if printf '%s' "$resp" | grep -q '"success":true'; then
    echo "  created with production branch '${PRODUCTION_BRANCH}'"
  else
    echo "  failed to create project:" >&2
    printf '%s\n' "$resp" | head -c 500 >&2
    exit 1
  fi
fi

say "Confirming the production branch"
current="$(api "${base}/${PROJECT}" | sed -n 's/.*"production_branch":"\([^"]*\)".*/\1/p' | head -n 1)"
if [ "$current" != "$PRODUCTION_BRANCH" ]; then
  api -X PATCH "${base}/${PROJECT}" --data "{\"production_branch\":\"${PRODUCTION_BRANCH}\"}" >/dev/null
  echo "  production branch set to '${PRODUCTION_BRANCH}'"
else
  echo "  production branch is '${PRODUCTION_BRANCH}'"
fi

say "Storing GitHub environment secrets"
for env in dev uat production; do
  gh secret set CLOUDFLARE_API_TOKEN  --repo "$REPO" --env "$env" --body "$CLOUDFLARE_API_TOKEN"
  gh secret set CLOUDFLARE_ACCOUNT_ID --repo "$REPO" --env "$env" --body "$CLOUDFLARE_ACCOUNT_ID"
  echo "  ${env}: secrets set"
done

say "Recording the project name"
gh variable set CLOUDFLARE_PROJECT_NAME --repo "$REPO" --body "$PROJECT" >/dev/null
echo "  CLOUDFLARE_PROJECT_NAME=${PROJECT}"

cat <<NEXT

==> Done.

  dev     -> https://dev.${PROJECT}.pages.dev
  uat     -> https://release.${PROJECT}.pages.dev
  prod    -> https://${PROJECT}.pages.dev (plus any custom domain you attach)

  The project has no Git connection, so Cloudflare will never build on push —
  deploys only happen through the GitHub Actions workflows, which is exactly
  what the release timing depends on.

  For a stricter production token, create a second Pages:Edit token and replace
  the 'production' environment secret with it.
NEXT
