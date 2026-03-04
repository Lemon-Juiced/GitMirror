#!/usr/bin/env bash
set -euo pipefail

# Simple Dry-Run test: fetch public repos for a GitHub user and print names
# Resolve users from (in order): script arguments, config.json GH_USERS array, config.json GH_USER
CONFIG_FILE="config.json"
USERS=()

# If arguments provided, use them as the list of users
if [ "$#" -gt 0 ]; then
	USERS=("$@")
else
	# Try to read GH_USERS array from config.json
	if [ -f "$CONFIG_FILE" ] && command -v jq >/dev/null 2>&1; then
		if jq -e 'has("GH_USERS")' "$CONFIG_FILE" >/dev/null 2>&1; then
			mapfile -t USERS < <(jq -r '.GH_USERS[]' "$CONFIG_FILE" 2>/dev/null || true)
		else
			# Fallback to single GH_USER key
			single=$(jq -r '.GH_USER // empty' "$CONFIG_FILE" 2>/dev/null || true)
			if [ -n "$single" ]; then
				USERS=("$single")
			fi
		fi
	fi
fi

if [ "${#USERS[@]}" -eq 0 ]; then
	echo "Usage: $0 <github-username>...  (or add GH_USERS array or GH_USER to config.json)" >&2
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

# Function: check public repos for a single user
check_user() {
		local USERNAME="$1"
		echo "Checking public GitHub repositories for ${USERNAME}..."

		local page=1
		local TOTAL=0
		while :; do
				local REPOS
				REPOS=$(curl -s "https://api.github.com/users/${USERNAME}/repos?per_page=100&page=${page}")

				# Detect GitHub API error (e.g., rate limit, not found)
				if echo "$REPOS" | jq -e 'has("message")' >/dev/null 2>&1; then
						local MSG
						MSG=$(echo "$REPOS" | jq -r '.message')
						echo "GitHub API error for ${USERNAME}: $MSG" >&2
						return 1
				fi

				# Filter out forks and count only original repositories
				local FILTERED
				FILTERED=$(echo "$REPOS" | jq '[.[] | select(.fork == false)]')
				local COUNT
				COUNT=$(echo "$FILTERED" | jq length)
				[ "$COUNT" -eq 0 ] && break

				# Print the names of the repositories found on this page with a green checkmark
				echo "$FILTERED" | jq -r '.[].name' | while read -r NAME; do
						printf '\033[32m✓\033[0m Found %s\n' "$NAME"
				done

				TOTAL=$((TOTAL + COUNT))
				((page++))
		done

		echo "" # blank line before summary
		if [ "$TOTAL" -eq 0 ]; then
				echo "No public repos found for ${USERNAME}" >&2
		else
			if [ "$TOTAL" -eq 1 ]; then
				echo "Found 1 Repository for ${USERNAME}"
			else
				echo "Found ${TOTAL} Repositories for ${USERNAME}"
			fi
		fi

		return 0
}

# Iterate over all users
for U in "${USERS[@]}"; do
		check_user "$U" || true
done

exit 0