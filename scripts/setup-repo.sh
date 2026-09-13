#!/usr/bin/env bash
# One-time repository bootstrap: branches, default branch, protection rules,
# labels and a sample milestone. Requires the gh CLI, authenticated with admin
# rights on the repository.
#
#   ./scripts/setup-repo.sh [owner/repo]
set -euo pipefail

REPO="${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
echo "Configuring ${REPO}"

say() { printf '\n==> %s\n' "$1"; }

say "Creating long-lived branches (dev, release, prod)"
base_sha="$(gh api "repos/${REPO}/git/ref/heads/$(gh api "repos/${REPO}" --jq .default_branch)" --jq .object.sha)"
for branch in dev release prod; do
  if gh api "repos/${REPO}/git/ref/heads/${branch}" >/dev/null 2>&1; then
    echo "  ${branch} already exists"
  else
    gh api -X POST "repos/${REPO}/git/refs" \
      -f ref="refs/heads/${branch}" -f sha="${base_sha}" >/dev/null
    echo "  created ${branch}"
  fi
done

say "Setting dev as the default branch"
# Required so GitHub auto-closes issues when a PR merges into dev.
gh api -X PATCH "repos/${REPO}" -f default_branch=dev >/dev/null
echo "  default branch = dev"

say "Enabling automatic deletion of head branches"
gh api -X PATCH "repos/${REPO}" -F delete_branch_on_merge=true >/dev/null

protect() {
  local branch="$1" reviews="$2"
  # Branch protection needs a public repository or a paid plan; a 403 here is
  # not fatal, the rest of the setup still applies.
  if ! gh api -X PUT "repos/${REPO}/branches/${branch}/protection" \
    --input - >/dev/null 2>&1 <<JSON
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "Linked issue has a milestone",
      "Branch naming convention",
      "Lint, test and build"
    ]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": ${reviews},
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": false
}
JSON
  then
    echo "  ⚠ could not protect ${branch} — branch protection requires a public repository or a paid plan"
    return 0
  fi
  echo "  protected ${branch}"
}

say "Applying branch protection"
protect dev 1
protect release 1
protect prod 1

say "Syncing labels"
while IFS= read -r line; do
  case "$line" in
    "- name: "*) name="${line#- name: }"; name="${name%\"}"; name="${name#\"}" ;;
    *"color: "*) color="${line#*color: }"; color="${color%\"}"; color="${color#\"}" ;;
    *"description: "*)
      desc="${line#*description: }"; desc="${desc%\"}"; desc="${desc#\"}"
      if gh label list --repo "${REPO}" --limit 200 --json name --jq '.[].name' | grep -Fxq "$name"; then
        gh label edit "$name" --repo "${REPO}" --color "$color" --description "$desc" >/dev/null
        echo "  updated ${name}"
      else
        gh label create "$name" --repo "${REPO}" --color "$color" --description "$desc" >/dev/null
        echo "  created ${name}"
      fi ;;
  esac
done < .github/labels.yml

say "Creating deployment environments"
owner_id="$(gh api "repos/${REPO}" --jq .owner.id)"
owner_type="$(gh api "repos/${REPO}" --jq .owner.type)"
reviewer_type="User"; [ "$owner_type" = "Organization" ] && reviewer_type="Team"

for env in dev uat production; do
  if [ "$env" = "production" ]; then
    # Required reviewers are what gate the promote-to-prod button.
    body="{\"reviewers\":[{\"type\":\"${reviewer_type}\",\"id\":${owner_id}}],\"deployment_branch_policy\":{\"protected_branches\":false,\"custom_branch_policies\":true}}"
  else
    body='{"deployment_branch_policy":null}'
  fi
  if printf '%s' "$body" | gh api -X PUT "repos/${REPO}/environments/${env}" --input - >/dev/null 2>&1; then
    echo "  created ${env}"
  else
    gh api -X PUT "repos/${REPO}/environments/${env}" >/dev/null 2>&1 \
      && echo "  created ${env} (without protection rules — requires a public repository or a paid plan)" \
      || echo "  ⚠ could not create ${env}"
  fi
done

say "Creating a sample milestone"
if gh api "repos/${REPO}/milestones?state=all" --jq '.[].title' | grep -Fxq "Sprint 1"; then
  echo "  Sprint 1 already exists"
else
  gh api -X POST "repos/${REPO}/milestones" \
    -f title="Sprint 1" \
    -f description="First small release. Closing this milestone bumps MINOR." >/dev/null
  echo "  created milestone 'Sprint 1'"
fi

cat <<'NEXT'

==> Done. Remaining manual steps (not scriptable from files):

  1. Add CLOUDFLARE_API_TOKEN (Pages:Edit) and CLOUDFLARE_ACCOUNT_ID as
     environment secrets on `dev`, `uat` and `production`:
       gh secret set CLOUDFLARE_API_TOKEN --env production
       gh secret set CLOUDFLARE_ACCOUNT_ID --env production
  2. Optionally set the repository variable CLOUDFLARE_PROJECT_NAME.
  3. Create the Cloudflare Pages project, set its production branch to `prod`,
     and disable its own "deploy on push" Git integration.
  4. If branch protection or environment reviewers were skipped above, make the
     repository public or upgrade the plan, then re-run this script.

  See docs/DEVOPS.md for details.
NEXT
