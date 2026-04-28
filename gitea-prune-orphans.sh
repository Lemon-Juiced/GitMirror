#!/usr/bin/env bash
set -euo pipefail

# gitea-prune-orphans.sh
# Deletes mirror repositories from a Gitea user account when the original
# repository no longer exists on any configured GitHub user/org in config.json.
# Usage: gitea-prune-orphans.sh [--dry] [config.json]

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry)
      DRY_RUN=true
      ;;
    *)
      CONFIG_FILE="$arg"
      ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required." >&2
  exit 2
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl is required." >&2
  exit 2
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Missing $CONFIG_FILE" >&2
  exit 2
fi

GITEA_BASE_URL=$(jq -r '.GITEA_URL // empty' "$CONFIG_FILE")
GITEA_TOKEN=$(jq -r '.GITEA_TOKEN // empty' "$CONFIG_FILE")
GITEA_USER=$(jq -r '.GITEA_USER // empty' "$CONFIG_FILE")
mapfile -t GH_USERS < <(jq -r '.GH_USERS[]? // empty' "$CONFIG_FILE")

if [ -z "$GITEA_BASE_URL" ] || [ -z "$GITEA_TOKEN" ] || [ -z "$GITEA_USER" ]; then
  echo "Error: GITEA_URL, GITEA_USER and GITEA_TOKEN must be set in $CONFIG_FILE" >&2
  exit 2
fi

GITEA_BASE_URL="${GITEA_BASE_URL%/}"
API_BASE="$GITEA_BASE_URL/api/v1"
AUTH_HDR=( -H "Authorization: token $GITEA_TOKEN" -H "Content-Type: application/json" )

PER_PAGE=50
page=1
found=0
orphans=0
deleted=0

echo "Gitea base: $GITEA_BASE_URL"
echo "User: $GITEA_USER"
if [ ${#GH_USERS[@]} -eq 0 ]; then
  echo "Warning: No GH_USERS configured - every mirror will be considered orphan unless you pass GH_USERS in $CONFIG_FILE" >&2
fi

while :; do
  url="$API_BASE/users/$GITEA_USER/repos?limit=$PER_PAGE&page=$page"
  resp=$(curl -sS "${AUTH_HDR[@]}" "$url") || { echo "Error fetching repos" >&2; exit 3; }
  count=$(echo "$resp" | jq 'length' 2>/dev/null || echo 0)
  [ "$count" -eq 0 ] && break

  while read -r repojson; do
    owner=$(echo "$repojson" | jq -r '.owner.login // .owner.username // empty')
    name=$(echo "$repojson" | jq -r '.name // empty')
    mirror=$(echo "$repojson" | jq -r '(.mirror // .is_mirror // .isMirror // false)')
    if [ -z "$owner" ] || [ -z "$name" ]; then
      continue
    fi
    if [ "$mirror" != "true" ] && [ "$mirror" != "1" ]; then
      continue
    fi

    found=$((found + 1))

    exists=false
    for gh in "${GH_USERS[@]}"; do
      code=$(curl -s -o /dev/null -w "%{http_code}" "https://api.github.com/repos/${gh}/${name}") || code=000
      if [ "$code" -eq 200 ]; then
        exists=true
        break
      elif [ "$code" -eq 403 ]; then
        echo "Warning: GitHub API returned 403 for ${gh}/${name} - you may be rate limited or require auth. Skipping check for this GH user." >&2
      fi
    done

    if [ "$exists" = false ]; then
      orphans=$((orphans + 1))
      if [ "$DRY_RUN" = true ]; then
        echo "Would delete mirror: ${owner}/${name} (no matching GitHub repo found)"
      else
        echo -n "Deleting ${owner}/${name}... "
        del_resp=$(curl -sS -o /dev/null -w "%{http_code}" -X DELETE "${AUTH_HDR[@]}" "$API_BASE/repos/$owner/$name" 2>&1) || del_resp=000
        if [ "$del_resp" -ge 200 ] && [ "$del_resp" -lt 300 ]; then
          echo "OK ($del_resp)"
          deleted=$((deleted + 1))
        else
          echo "FAILED ($del_resp)"
        fi
      fi
    fi
  done < <(echo "$resp" | jq -c '.[]')

  page=$((page + 1))
done

echo "Summary: mirror repos scanned=$found, orphans=$orphans, deleted=$deleted"

if [ "$DRY_RUN" = true ]; then
  echo "Dry run only. Re-run without --dry to actually delete orphaned mirrors."
fi

exit 0