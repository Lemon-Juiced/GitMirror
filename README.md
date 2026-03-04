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

## Tests
`git-mirror-ghtest.sh` queries the GitHub API for a user's public repositories and prints each repo name (e.g. `✓ Found <repo-name>`).  
The test does not perform cloning or mirroring.  

## Notes
- The GitHub API has rate limits for unauthenticated requests, so this can fail.  
- Keep `GITEA_TOKEN` secret — **DO NOT** commit it to version control. (This is why config.json is in .gitignore).