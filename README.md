# Git Mirror
Small utilities to mirror a GitHub user's public repositories to a self-hosted Gitea instance.  

## Prerequisites
- curl  
- jq  
  
You can install these separately or run `get-prereqs.sh`.  

## Configuration
The tools are configured via `config.json`. An example is provided in `config_example.json`.  
Example `config.json`:  
```json
{  
  "GH_USERS": [
    "your_github_username0",
    "your_github_username1"
  ],
  "GH_EXCLUDE_REPOS": [
    "repo-to-exclude0",
    "repo-to-exclude1"
  ],
  "GITEA_URL": "https://git.example.com",  
  "GITEA_USER": "your_gitea_username",  
  "GITEA_TOKEN": "gitea_xxxxxxxxxxxxx"  
}  
```

## Usage
- Set all programs in this repository as executable:  
  `bash chmodder.sh`  
- Mirror repositories (creates mirrors on the configured Gitea):  
  `bash git-mirror.sh`  
- Dry-run test (fetches public repos and prints names):  
  `bash git-mirror-ghtest.sh <github_usernames>`  
  If you omit `<github_usernames>` the test script will read `GH_USERS` from `config.json`.  
- Sync all mirrored repositories for a user on Gitea:  
  `bash gitea_sync_all.sh`
- Create a Gitea user account:  
  `bash gitea-create-owner.sh <name> [password] [email]`  
  - `<name>` is required.  
  - `[password]` is optional, you will be prompted for one if omitted. Passwords must be at least 8 characters.  
  - `[email]` is optional, defaults to `name@users.noreply.github.com` if omitted.  
- Create a Gitea organisation:  
  `bash gitea-create-owner.sh -o <name>`  
- Delete a Gitea user or organisation by name:  
  `bash gitea-del-user.sh <name>`   
- Remove mirror repos that no longer exist on GitHub:
  `bash gitea-prune-orphans.sh`
- Preview orphan mirror deletions without deleting anything:
  `bash gitea-prune-orphans.sh --dry`
  By default, the script reads `config.json` from the same directory as the script.

## Tests
`git-mirror-ghtest.sh` is a dry-run check for the mirror input set. It:  
- Reads users from script arguments, or from `GH_USERS` in `config.json` when no arguments are provided  
- Queries each user's public repositories from the GitHub API  
- Skips forked repositories  
- Skips repositories listed in `GH_EXCLUDE_REPOS` (prints `! Excluding <repo> ...`)  
- Prints non-excluded repositories as `✓ Found <repo-name>`  

It does **not** clone, create, or sync mirrors in Gitea.  

## Notes
- The GitHub API has rate limits for unauthenticated requests, so this can fail.  
- Keep `GITEA_TOKEN` secret! — **DO NOT** commit it to version control. (This is why config.json is in .gitignore).
  
### Optional: Man Pages
The primary way to use Git Mirror is still running the scripts directly as shown above.
Man pages are available as an optional convenience for users who prefer `man` documentation.

- Man page sources are in `man/man1/`.
- Quick preview without installing:
  `man -l man/man1/git-mirror.sh.1`
- Optional local install (Linux):
  `sudo install -m 0644 man/man1/*.1 /usr/local/share/man/man1/ && sudo mandb`