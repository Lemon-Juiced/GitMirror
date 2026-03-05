#!/usr/bin/env bash
set -euo pipefail

# Simple Dry-Run test: fetch public repos for a GitHub user and print names
# Resolve users from (in order): script arguments, config.json GH_USERS array
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
		fi
	fi
fi

if [ "${#USERS[@]}" -eq 0 ]; then
	echo "Usage: $0 <github-username>...  (or add GH_USERS array to config.json)" >&2
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

# Read exclude list from config.json (if present)
EXCLUDES=()
if [ -f "$CONFIG_FILE" ] && command -v jq >/dev/null 2>&1; then
    if jq -e 'has("GH_EXCLUDE_REPOS")' "$CONFIG_FILE" >/dev/null 2>&1; then
        mapfile -t EXCLUDES < <(jq -r '.GH_EXCLUDE_REPOS[]' "$CONFIG_FILE" 2>/dev/null || true)
    fi
fi

# Normalize exclude entries (strip trailing .git for comparison)
EXCLUDES_NORM=()
for e in "${EXCLUDES[@]}"; do
    EXCLUDES_NORM+=("${e%.git}")
done

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

				# Iterate repositories on this page, respecting excludes
				local excluded_count=0
				while read -r repojson; do
					name=$(echo "$repojson" | jq -r '.name // empty')
					clone_url=$(echo "$repojson" | jq -r '.clone_url // empty')
					html_url=$(echo "$repojson" | jq -r '.html_url // empty')

					# Normalize urls for comparison (strip .git)
					clone_norm="${clone_url%.git}"
					html_norm="${html_url%.git}"

					# Check excludes
					excluded=false
					for ex in "${EXCLUDES_NORM[@]}"; do
						if [ -n "$ex" ] && { [ "$ex" = "$clone_norm" ] || [ "$ex" = "$html_norm" ]; }; then
							excluded=true
							break
						fi
					done

					if [ "$excluded" = true ]; then
						# Yellow highlight for excluded repos
						printf '\033[33m!\033[0m Excluding %s (%s)\n' "$name" "${clone_url:-$html_url}"
						excluded_count=$((excluded_count+1))
						continue
					fi

					# Not excluded: print green check and count
					printf '\033[32m✓\033[0m Found %s\n' "$name"
					TOTAL=$((TOTAL + 1))
				done < <(echo "$FILTERED" | jq -c '.[]')

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