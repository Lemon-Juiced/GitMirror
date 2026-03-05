#!/usr/bin/env bash
set -euo pipefail

# git-mirror.sh
# Mirrors public GitHub repos for one or more users into a Gitea instance using the migration API.
# Configuration is read from config.json (see config_example.json).

CONFIG_FILE="config.json"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Missing ${CONFIG_FILE}. Copy config_example.json to ${CONFIG_FILE} and fill in values." >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to read ${CONFIG_FILE}." >&2
  exit 2
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required." >&2
  exit 2
fi

# Load configuration values from config.json
mapfile -t GH_USERS < <(jq -r '.GH_USERS[]?' "$CONFIG_FILE")
mapfile -t GH_EXCLUDE_REPOS < <(jq -r '.GH_EXCLUDE_REPOS[]?' "$CONFIG_FILE")
GITEA_URL=$(jq -r '.GITEA_URL // empty' "$CONFIG_FILE")
GITEA_USER=$(jq -r '.GITEA_USER // empty' "$CONFIG_FILE")
GITEA_TOKEN=$(jq -r '.GITEA_TOKEN // empty' "$CONFIG_FILE")

if [ "${#GH_USERS[@]}" -eq 0 ] || [ -z "$GITEA_URL" ] || [ -z "$GITEA_TOKEN" ]; then
  echo "Please set GH_USERS, GITEA_URL and GITEA_TOKEN in ${CONFIG_FILE}." >&2
  exit 2
fi

# Normalize excluded repository URLs for comparison (strip trailing .git)
GH_EXCLUDE_REPOS_NORM=()
for excluded_repo in "${GH_EXCLUDE_REPOS[@]}"; do
  GH_EXCLUDE_REPOS_NORM+=("${excluded_repo%.git}")
done

echo "Fetching existing Gitea repositories..."

GITEA_REPOS=$(curl -s \
  -H "Authorization: token ${GITEA_TOKEN}" \
  "${GITEA_URL}/api/v1/user/repos?limit=1000" \
  | jq -r '.[].name')

repo_exists() {
  echo "$GITEA_REPOS" | grep -qx "$1"
}

MIRRORED=0
for GH_USER in "${GH_USERS[@]}"; do
  echo "Fetching public GitHub repositories for ${GH_USER}..."

  page=1
  while :; do
    REPOS=$(curl -s "https://api.github.com/users/${GH_USER}/repos?per_page=100&page=${page}")

    # Detect GitHub API error (e.g., rate limit, not found)
    if echo "$REPOS" | jq -e 'has("message")' >/dev/null 2>&1; then
      MSG=$(echo "$REPOS" | jq -r '.message')
      echo "GitHub API error for ${GH_USER}: $MSG" >&2
      break
    fi

    COUNT=$(echo "$REPOS" | jq length)
    [ "$COUNT" -eq 0 ] && break

    while read -r repo; do
      NAME=$(echo "$repo" | jq -r '.name')
      CLONE_URL=$(echo "$repo" | jq -r '.clone_url')
      HTML_URL=$(echo "$repo" | jq -r '.html_url')
      IS_FORK=$(echo "$repo" | jq -r '.fork')

      CLONE_URL_NORM="${CLONE_URL%.git}"
      HTML_URL_NORM="${HTML_URL%.git}"

      EXCLUDED=false
      for excluded_repo in "${GH_EXCLUDE_REPOS_NORM[@]}"; do
        if [ -n "$excluded_repo" ] && { [ "$excluded_repo" = "$CLONE_URL_NORM" ] || [ "$excluded_repo" = "$HTML_URL_NORM" ]; }; then
          EXCLUDED=true
          break
        fi
      done

      if [ "$EXCLUDED" = true ]; then
        echo "Skipping $NAME (excluded)"
        continue
      fi

      if [ "$IS_FORK" = "true" ]; then
        echo "Skipping $NAME (fork)"
        continue
      fi

      if repo_exists "$NAME"; then
        echo "Skipping $NAME (already exists)"
        continue
      fi

      echo "Creating mirror for $NAME..."

      curl -s -X POST \
        -H "Authorization: token ${GITEA_TOKEN}" \
        -H "Content-Type: application/json" \
        "${GITEA_URL}/api/v1/repos/migrate" \
        -d "{
          \"clone_addr\": \"${CLONE_URL}\",
          \"repo_name\": \"${NAME}\",
          \"mirror\": true,
          \"private\": false,
          \"service\": \"git\"
        }" > /dev/null

      printf '\033[32m✓\033[0m Mirrored %s\n' "$NAME"
      MIRRORED=$((MIRRORED + 1))
    done < <(echo "$REPOS" | jq -c '.[]')

    ((page++))
  done
done

echo "" # Create a blank line before the summary

if [ "$MIRRORED" -eq 0 ]; then
  echo "No repositories were mirrored."
elif [ "$MIRRORED" -eq 1 ]; then
  echo "Mirrored 1 Repository"
else
  echo "Mirrored ${MIRRORED} Repositories"
fi

echo "Done."

exit 0