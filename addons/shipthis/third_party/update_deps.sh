#!/bin/bash
# update_deps.sh - Fetch third-party dependencies from GitHub
# Just run: ./update_deps.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

fetch_github_addon() {
    local name="$1"
    local repo="$2"
    local branch="$3"
    local source_path="$4"
    local root_files="$5"
    
    local dest_dir="$SCRIPT_DIR/$name"
    local tarball_url="https://github.com/$repo/archive/refs/heads/$branch.tar.gz"
    local repo_name="${repo##*/}"
    
    echo "Fetching $name from $repo..."
    
    curl -sL "$tarball_url" | tar -xz -C /tmp
    rm -rf "$dest_dir"
    cp -r "/tmp/${repo_name}-$branch/$source_path" "$dest_dir"
    
    for file in $root_files; do
        cp "/tmp/${repo_name}-$branch/$file" "$dest_dir/" 2>/dev/null || true
    done
    
    rm -rf "/tmp/${repo_name}-$branch"
    echo "  -> $dest_dir"
}

# === DEPENDENCIES ===
fetch_github_addon "godot-socketio" "msabaeian/godot-socketio" "main" "addons/godot-socketio" "LICENSE README.md"
# Add more deps here as needed

echo "Done!"
