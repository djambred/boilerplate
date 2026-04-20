#!/bin/bash
set -euo pipefail

# Check for required input
if [ $# -ne 1 ]; then
  echo "❌ Usage: $0 <repo-prefix> (e.g., dev- or test-)"
  exit 1
fi

PREFIX="$1"

# Load GitHub credentials from files
GITHUB_USER=$(<.github-user)
GITHUB_TOKEN=$(<.github-token)

echo "📥 Fetching repositories for user: $GITHUB_USER with prefix: $PREFIX"

# Fetch all repos with pagination
PAGE=1
REPOS=""
while true; do
  RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/user/repos?per_page=100&page=$PAGE")

  # Check for API errors
  ERROR=$(echo "$RESPONSE" | jq -r '.message // empty' 2>/dev/null || true)
  if [ -n "$ERROR" ]; then
    echo "❌ GitHub API error: $ERROR"
    exit 1
  fi

  PAGE_REPOS=$(echo "$RESPONSE" | jq -r --arg prefix "^$PREFIX$" \
    '.[] | select(.name | test($prefix)) | .full_name' 2>/dev/null || true)

  if [ -n "$PAGE_REPOS" ]; then
    REPOS="${REPOS}${REPOS:+$'\n'}${PAGE_REPOS}"
  fi

  COUNT=$(echo "$RESPONSE" | jq '. | length' 2>/dev/null || echo 0)
  if [ "$COUNT" -lt 100 ]; then
    break
  fi
  PAGE=$((PAGE + 1))
done

# Check if any matching repos
if [ -z "$REPOS" ]; then
  echo "ℹ️ No repositories found with prefix '$PREFIX'"
  exit 0
fi

# Confirm before deleting
echo "❗ Repositories to be deleted:"
echo "$REPOS" | sed 's/^/  🔻 /'
read -rp "⚠️ Are you sure you want to delete these repositories? (y/N) " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
  echo "❌ Cancelled."
  exit 1
fi

# Delete repos
for REPO in $REPOS; do
  echo "🚨 Deleting $REPO..."
  curl -s -X DELETE -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/$REPO"
done

echo "✅ Done."
