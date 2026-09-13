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
  gh api -X PUT "repos/${REPO}/branches/${branch}/protection" \
    --input - >/dev/null <<JSON
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

  1. Settings > Environments: create `dev`, `uat` and `production`.
     Add required reviewers to `production` — they gate the promote button.
  2. Add CLOUDFLARE_API_TOKEN (Pages:Edit) and CLOUDFLARE_ACCOUNT_ID as
     secrets, scoped per environment.
  3. Optionally set the repository variable CLOUDFLARE_PROJECT_NAME.
  4. Create the Cloudflare Pages project, set its production branch to `prod`,
     and disable its own "deploy on push" Git integration.

  See docs/DEVOPS.md for details.
NEXT
