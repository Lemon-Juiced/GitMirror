#!/usr/bin/env bash
set -euo pipefail

# gitea-sync-all.sh
# Triggers mirror syncs for all mirror repos in a Gitea instance for a user.
# Requires: curl, jq

CONFIG_FILE="${1:-config.json}"

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required. Install jq and try again." >&2
  exit 2
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl is required. Install curl and try again." >&2
  exit 2
fi

 # Read required config keys 
GITEA_BASE_URL="$(jq -r '.GITEA_URL // empty' "$CONFIG_FILE" 2>/dev/null || true)"
GITEA_TOKEN="$(jq -r '.GITEA_TOKEN // empty' "$CONFIG_FILE" 2>/dev/null || true)"
GITEA_USER="$(jq -r '.GITEA_USER // empty' "$CONFIG_FILE" 2>/dev/null || true)"

if [ -z "$GITEA_BASE_URL" ]; then
  echo "Error: Gitea base URL not found in $CONFIG_FILE." >&2
  exit 2
fi
if [ -z "$GITEA_TOKEN" ]; then
  echo "Error: Gitea API token not found in $CONFIG_FILE." >&2
  exit 2
fi
if [ -z "$GITEA_USER" ]; then
  echo "Error: Gitea username not found in $CONFIG_FILE." >&2
  exit 2
fi

# Normalize base URL and set API base
GITEA_BASE_URL="${GITEA_BASE_URL%/}"
API_BASE="$GITEA_BASE_URL/api/v1"

echo "Gitea base: $GITEA_BASE_URL"
echo "User: $GITEA_USER"

AUTH_HDR=( -H "Authorization: token $GITEA_TOKEN" -H "Content-Type: application/json" )
PER_PAGE=50
page=1
synced=0
found=0

# Only list repos for the configured user
while :; do
  url="$API_BASE/users/$GITEA_USER/repos?limit=$PER_PAGE&page=$page"

  resp=$(curl -sS "${AUTH_HDR[@]}" "$url") || {
    echo "Error fetching repo list from $url" >&2
    exit 3
  }

  count=$(echo "$resp" | jq 'length' 2>/dev/null || echo 0)
  if [ "$count" -eq 0 ]; then
    break
  fi

  echo "Processing page $page (repos: $count)"

  # Use process substitution so counters update in this shell
  while read -r repojson; do
    owner=$(echo "$repojson" | jq -r '.owner.login // .owner.username // empty')
    name=$(echo "$repojson" | jq -r '.name // empty')
    mirror=$(echo "$repojson" | jq -r '(.mirror // .is_mirror // .isMirror // false)')
    if [ -z "$owner" ] || [ -z "$name" ]; then
      continue
    fi
    if [ "$mirror" = "true" ] || [ "$mirror" = "1" ]; then
      found=$((found+1))
      endpoint="$API_BASE/repos/$owner/$name/mirror-sync"
      printf "Syncing %s/%s... " "$owner" "$name"
      code=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "${AUTH_HDR[@]}" "$endpoint" ) || code=000
      if [ "$code" -ge 200 ] && [ "$code" -lt 300 ]; then
        echo "OK ($code)"
        synced=$((synced+1))
      else
        echo "FAILED ($code) - $endpoint"
      fi
    fi
  done < <(echo "$resp" | jq -c '.[]')

  page=$((page+1))
done

echo "Done. Mirror repos found: $found; successfully triggered: $synced"
exit 0
