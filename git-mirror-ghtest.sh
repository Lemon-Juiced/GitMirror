#!/usr/bin/env bash
set -euo pipefail

# Simple Dry-Run test: fetch public repos for a GitHub user and print names
# Resolve GH_USER from (in order): script argument, config.json
ARG_USER="${1:-}"
GH_USER="${ARG_USER:-}"
CONFIG_FILE="config.json"

if [ -z "$GH_USER" ] && [ -f "$CONFIG_FILE" ]; then
	if command -v jq >/dev/null 2>&1; then
		GH_USER=$(jq -r '.GH_USER // empty' "$CONFIG_FILE" 2>/dev/null || true)
	fi
fi

if [ -z "$GH_USER" ]; then
	echo "Usage: $0 <github-username>  (or add GH_USER to config.json)" >&2
	exit 2
fi

# Basic runtime requirements
if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required." >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required." >&2
  exit 2
fi

echo "Checking public GitHub repositories for ${GH_USER}..."

page=1
TOTAL=0
while :; do
	REPOS=$(curl -s "https://api.github.com/users/${GH_USER}/repos?per_page=100&page=${page}")

	# Detect GitHub API error (e.g., rate limit, not found)
	if echo "$REPOS" | jq -e 'has("message")' >/dev/null 2>&1; then
		MSG=$(echo "$REPOS" | jq -r '.message')
		echo "GitHub API error: $MSG" >&2
		exit 3
	fi

	# Filter out forks and count only original repositories
	FILTERED=$(echo "$REPOS" | jq '[.[] | select(.fork == false)]')
	COUNT=$(echo "$FILTERED" | jq length)
	[ "$COUNT" -eq 0 ] && break

    # Print the names of the repositories found on this page with a green checkmark
	echo "$FILTERED" | jq -r '.[].name' | while read -r NAME; do
		printf '\033[32m✓\033[0m Found %s\n' "$NAME"
	done

	TOTAL=$((TOTAL + COUNT))
	((page++))
done

echo "" # Create a blank line before the summary

if [ "$TOTAL" -eq 0 ]; then
	echo "No public repos found for ${GH_USER}" >&2
	exit 1
else
  if [ "$TOTAL" -eq 1 ]; then
    echo "Found 1 Repository"
  else
    echo "Found ${TOTAL} Repositories"
  fi
fi

exit 0
