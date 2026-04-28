#!/usr/bin/env bash
set -euo pipefail

# gitea-del-user.sh
# Deletes a user account or organisation on a Gitea instance by name.
#
# Usage:
#   gitea-del-user.sh <name>

CONFIG_FILE="config.json"

if [ $# -ne 1 ]; then
  echo "Usage: $0 <name>" >&2
  exit 2
fi

NAME="$1"

if ! command -v curl >/dev/null 2>&1; then echo "Error: curl is required." >&2; exit 2; fi
if ! command -v jq >/dev/null 2>&1; then echo "Error: jq is required." >&2; exit 2; fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Missing ${CONFIG_FILE}." >&2
  exit 2
fi

GITEA_URL=$(jq -r '.GITEA_URL // empty' "$CONFIG_FILE")
GITEA_TOKEN=$(jq -r '.GITEA_TOKEN // empty' "$CONFIG_FILE")

if [ -z "$GITEA_URL" ] || [ -z "$GITEA_TOKEN" ]; then
  echo "Error: GITEA_URL and GITEA_TOKEN must be set in ${CONFIG_FILE}." >&2
  exit 2
fi

GITEA_URL="${GITEA_URL%/}"
API_BASE="$GITEA_URL/api/v1"

org_code=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: token ${GITEA_TOKEN}" \
  "${API_BASE}/orgs/${NAME}")

user_code=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: token ${GITEA_TOKEN}" \
  "${API_BASE}/users/${NAME}")

owner_type=""
if [ "$org_code" -eq 200 ]; then
  owner_type="organisation"
elif [ "$user_code" -eq 200 ]; then
  owner_type="user"
else
  echo "Error: owner '${NAME}' not found." >&2
  exit 1
fi

if [ "$owner_type" = "organisation" ]; then
  resp=$(curl -s -X DELETE \
    -H "Authorization: token ${GITEA_TOKEN}" \
    "${API_BASE}/orgs/${NAME}" \
    -w $'\n%{http_code}')
else
  resp=$(curl -s -X DELETE \
    -H "Authorization: token ${GITEA_TOKEN}" \
    "${API_BASE}/admin/users/${NAME}" \
    -w $'\n%{http_code}')
fi

body="${resp%$'\n'*}"
code="${resp##*$'\n'}"

if [ "$code" -ge 200 ] && [ "$code" -lt 300 ]; then
  if [ "$owner_type" = "organisation" ]; then
    printf '\033[32m✓\033[0m Organisation deleted: %s\n' "$NAME"
  else
    printf '\033[32m✓\033[0m User deleted: %s\n' "$NAME"
  fi
  exit 0
fi

err=$(echo "$body" | jq -r '.message // .error // empty' 2>/dev/null || echo "$body")
case "$err" in
  *Repo*|*repo*|*repositories*|*Repository*)
    echo "Error deleting ${owner_type} '${NAME}': manual intervention required to remove repositories before deleting owner." >&2
    ;;
  *)
    echo "Error deleting ${owner_type} '${NAME}': ${err}" >&2
    echo "Manual intervention may be required to remove repositories before deleting owner." >&2
    ;;
esac
exit 1
