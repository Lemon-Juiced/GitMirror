#!/usr/bin/env bash

# Gets the prerequisites for the git-mirror.sh script (for Ubuntu/Debian). 
# git-mirror.sh requires: curl and jq.

set -euo pipefail

if ! command -v curl &> /dev/null; then
    echo "curl is not installed. Installing..."
    sudo apt-get update
    sudo apt-get install -y curl
else
    echo "curl is already installed."
fi

if ! command -v jq &> /dev/null; then
    echo "jq is not installed. Installing..."
    sudo apt-get update
    sudo apt-get install -y jq
else
    echo "jq is already installed."
fi

echo "All prerequisites are installed."
echo "curl version: $(curl --version | head -n 1)"
echo "jq version: $(jq --version)"