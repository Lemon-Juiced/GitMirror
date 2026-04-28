#!/usr/bin/env bash
set -euo pipefail

# gitea-create-owner.sh (create_repo_owner.sh)
# Creates a user account or organisation on a Gitea instance.
#
# Usage:
#   gitea-create-owner.sh [-o] <name> [password] [email]
#
# Options:
#   -o          Create an organisation instead of a user account (no password needed)
#
# Arguments:
#   name        Username or organisation name to create
#   password    Password for the new user account (prompted if omitted)
#   email       Email address for the new user (default: name@users.noreply.github.com)
#
# Creating a user requires an admin-level GITEA_TOKEN.

IS_ORG=false
CONFIG_FILE="config.json"

while getopts ":o" opt; do
  case "$opt" in
    o) IS_ORG=true ;;
    \?) echo "Error: unknown option -${OPTARG}." >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

if [ $# -lt 1 ]; then
  echo "Usage: $0 [-o] <name> [password] [email]" >&2
  exit 2
fi

NAME="$1"
PASSWORD="${2:-}"
EMAIL="${3:-}"

if ! command -v curl >/dev/null 2>&1; then echo "Error: curl is required." >&2; exit 2; fi
if ! command -v jq  >/dev/null 2>&1; then echo "Error: jq is required."   >&2; exit 2; fi

# Load connection settings from config file
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

# Check whether the name is already taken (users and orgs share the same namespace)
http_code=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: token ${GITEA_TOKEN}" \
  "${API_BASE}/users/${NAME}")

if [ "$http_code" -eq 200 ]; then
  if [ "$IS_ORG" = true ]; then
    echo "Error: organisation '${NAME}' already exists and cannot be recreated." >&2
  else
    echo "Error: user '${NAME}' already exists and cannot be recreated." >&2
  fi
  exit 1
fi

# Create organisation
if [ "$IS_ORG" = true ]; then
  resp=$(curl -s -X POST \
    -H "Authorization: token ${GITEA_TOKEN}" \
    -H "Content-Type: application/json" \
    "${API_BASE}/orgs" \
    -d "{\"username\": \"${NAME}\", \"visibility\": \"public\"}" \
    -w $'\n%{http_code}')
  body="${resp%$'\n'*}"
  code="${resp##*$'\n'}"

  if [ "$code" -ge 200 ] && [ "$code" -lt 300 ]; then
    printf '\033[32m✓\033[0m Organisation created: %s\n' "$NAME"
  else
    err=$(echo "$body" | jq -r '.message // .error // empty' 2>/dev/null || echo "$body")
    echo "Error creating organisation '${NAME}': ${err}" >&2
    exit 1
  fi

# Create user account
else
  if [ -z "$PASSWORD" ]; then
    read -rsp "Password for new user '${NAME}': " PASSWORD
    echo
  fi
  if [ -z "$PASSWORD" ]; then
    echo "Error: a password is required to create a user account." >&2
    exit 2
  fi

  [ -z "$EMAIL" ] && EMAIL="${NAME}@users.noreply.github.com"

  resp=$(curl -s -X POST \
    -H "Authorization: token ${GITEA_TOKEN}" \
    -H "Content-Type: application/json" \
    "${API_BASE}/admin/users" \
    -d "{
      \"username\": \"${NAME}\",
      \"email\": \"${EMAIL}\",
      \"password\": \"${PASSWORD}\",
      \"must_change_password\": false
    }" \
    -w $'\n%{http_code}')
  body="${resp%$'\n'*}"
  code="${resp##*$'\n'}"

  if [ "$code" -ge 200 ] && [ "$code" -lt 300 ]; then
    printf '\033[32m✓\033[0m User created: %s (%s)\n' "$NAME" "$EMAIL"
  else
    err=$(echo "$body" | jq -r '.message // .error // empty' 2>/dev/null || echo "$body")
    echo "Error creating user '${NAME}': ${err}" >&2
    exit 1
  fi
fi

exit 0
