#!/bin/bash

# Provide facilities to represent and manipulate the current workspace (Obsidian tabs, external applications, etc.) as a folder-file.
# A workspace-ff is tied to an Obsidian workspace, which is tied to a vault.

# Prevent from being sourced more than once
[ -n "${_OBS_WORKSPACE_FF_SH:-}" ] && return || _OBS_WORKSPACE_FF_SH=1

# Define the library directory
lib_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# Dependencies
. "$lib_dir/obs.vaults.sh"
. "$lib_dir/obs.ws.sh"

# Default values
# ff means "folder-file"
obs_defaults_workspace_ff_name="Espace de travail"

# Retrieve the current workspace folder-file.
# For now, we just try to retrieve it from the list the paths to the left of the active workspace.
# If there is such path which matches the default workspace folder-file name, we print it.
# Otherwise, we print nothing.
# This will be improved later.
obs.workspace_ff.current(){
    vault_dir="${1:-$(obs.current_vault.path)}"
    obs.current_vault.notes_in_active_workspace "$vault_dir" "left" | \
        obs.paths.only_matching_basename "${obs_defaults_workspace_ff_name}.md"
}

# Create the workspace folder-file if it does not exist.
obs.workspace_ff.create(){
    vault_dir="${1:-$(obs.current_vault.path)}"
    workspace_ff="$vault_dir/${obs_defaults_workspace_ff_name}"
    # workspace_ff should not exist yet
    if [ -e "$workspace_ff" ]; then
        printf 'Error: %s already exists\n' "$workspace_ff"
        exit 1
    fi
    mkdir -p "$workspace_ff" || exit 1
    f="$workspace_ff/$obs_defaults_workspace_ff_name.md"
    touch "$f"
}
