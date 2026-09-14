#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# FILL THIS IN, then run:  ./scripts/setup-cloudflare.sh
# ---------------------------------------------------------------------------
# Create the token at https://dash.cloudflare.com/profile/api-tokens
#   Create Token -> Custom token -> Permissions:
#     Account | Cloudflare Pages | Edit
CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-PASTE_YOUR_PAGES_EDIT_TOKEN_HERE}"

# Leave as-is to detect it automatically from the token.
CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-}"

# Cloudflare Pages project to create/use, and the branch that is "production".
PROJECT_NAME="${CLOUDFLARE_PROJECT_NAME:-flow-github-pages}"
PRODUCTION_BRANCH="${PRODUCTION_BRANCH:-prod}"
# ---------------------------------------------------------------------------
#
# What this does:
#   1. verifies the token and works out the account ID
#   2. creates the Pages project with `prod` as the production branch, with no
#      Git connection so Cloudflare never builds on push
#   3. stores CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID as GitHub
#      environment secrets on dev, uat and production
#
# Everything is idempotent — safe to re-run.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ "$CLOUDFLARE_API_TOKEN" = "PASTE_YOUR_PAGES_EDIT_TOKEN_HERE" ] || [ -z "$CLOUDFLARE_API_TOKEN" ]; then
  cat >&2 <<'ERR'
No API token set.

Either edit the CLOUDFLARE_API_TOKEN line at the top of this file, or run:

  CLOUDFLARE_API_TOKEN=<token> ./scripts/setup-cloudflare.sh

Create the token at https://dash.cloudflare.com/profile/api-tokens with the
"Account | Cloudflare Pages | Edit" permission.
ERR
  exit 1
fi

REPO="${REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"

say() { printf '\n==> %s\n' "$1"; }
cf() {
  curl -sS \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "$@"
}
ok() { grep -q '"success":true' <<<"$1"; }
field() { sed -n "s/.*\"$2\":\"\([^\"]*\)\".*/\1/p" <<<"$1" | head -n 1; }

say "Verifying the token"
verify="$(cf https://api.cloudflare.com/client/v4/user/tokens/verify)"
if ! ok "$verify"; then
  echo "  Cloudflare rejected the token:" >&2
  head -c 400 <<<"$verify" >&2; echo >&2
  exit 1
fi
echo "  token is valid"

if [ -z "$CLOUDFLARE_ACCOUNT_ID" ]; then
  say "Detecting the account ID"
  accounts="$(cf https://api.cloudflare.com/client/v4/accounts)"
  if ok "$accounts"; then
    CLOUDFLARE_ACCOUNT_ID="$(field "$accounts" id)"
  fi
  if [ -z "$CLOUDFLARE_ACCOUNT_ID" ]; then
    cat >&2 <<'ERR'
  Could not list accounts with this token (a Pages-only token often cannot —
  that is expected). Set it explicitly instead:

    CLOUDFLARE_ACCOUNT_ID=<id> ./scripts/setup-cloudflare.sh

  The ID is in the right-hand sidebar of any Cloudflare dashboard page, or in
  the dashboard URL: dash.cloudflare.com/<account-id>/...
ERR
    exit 1
  fi
  echo "  account ${CLOUDFLARE_ACCOUNT_ID}"
else
  say "Using the supplied account ID"
  echo "  account ${CLOUDFLARE_ACCOUNT_ID}"
fi

base="https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects"

say "Pages project '${PROJECT_NAME}'"
existing="$(cf "${base}/${PROJECT_NAME}")"
if ok "$existing"; then
  echo "  already exists"
  current="$(field "$existing" production_branch)"
  if [ "$current" != "$PRODUCTION_BRANCH" ]; then
    cf -X PATCH "${base}/${PROJECT_NAME}" \
      --data "{\"production_branch\":\"${PRODUCTION_BRANCH}\"}" >/dev/null
    echo "  production branch changed from '${current}' to '${PRODUCTION_BRANCH}'"
  else
    echo "  production branch is '${PRODUCTION_BRANCH}'"
  fi
else
  created="$(cf -X POST "$base" \
    --data "{\"name\":\"${PROJECT_NAME}\",\"production_branch\":\"${PRODUCTION_BRANCH}\"}")"
  if ok "$created"; then
    echo "  created with production branch '${PRODUCTION_BRANCH}'"
  else
    echo "  could not create the project:" >&2
    head -c 600 <<<"$created" >&2; echo >&2
    exit 1
  fi
fi

say "Storing GitHub environment secrets"
for env in dev uat production; do
  gh secret set CLOUDFLARE_API_TOKEN  --repo "$REPO" --env "$env" --body "$CLOUDFLARE_API_TOKEN" >/dev/null
  gh secret set CLOUDFLARE_ACCOUNT_ID --repo "$REPO" --env "$env" --body "$CLOUDFLARE_ACCOUNT_ID" >/dev/null
  echo "  ${env}: secrets set"
done

say "Recording the project name"
gh variable set CLOUDFLARE_PROJECT_NAME --repo "$REPO" --body "$PROJECT_NAME" >/dev/null
echo "  CLOUDFLARE_PROJECT_NAME=${PROJECT_NAME}"

cat <<NEXT

==> Done.

  dev  -> https://dev.${PROJECT_NAME}.pages.dev
  uat  -> https://release.${PROJECT_NAME}.pages.dev
  prod -> https://${PROJECT_NAME}.pages.dev

  The project has no Git connection, so Cloudflare never builds on push —
  deploys happen only through the GitHub Actions workflows, which is what the
  release timing depends on.

  If you pasted the token into this file, clear it again before committing:
    git checkout -- scripts/setup-cloudflare.sh

  For stricter separation, create a second Pages:Edit token and replace just
  the 'production' environment secret with it.
NEXT
