#!/usr/bin/env bash
set -euo pipefail

# chmod +x All .sh files in the current directory
for file in *.sh; do
    if [ -f "$file" ]; then
        chmod +x "$file"
        echo "Set executable permission for $file"
    fi
done
