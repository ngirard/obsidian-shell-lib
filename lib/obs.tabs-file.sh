#!/bin/bash

# Prevent from being sourced more than once
[ -n "${_OBS_TABS_FILE_SH:-}" ] && return || _OBS_TABS_FILE_SH=1

if [ -z "${_osl_dir}" ]; then
    # Define the library directory if not defined
    _osl_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
fi

# Dependencies
. "$_osl_dir/obs.core.sh"
. "$_osl_dir/obs.vaults.sh"
. "$_osl_dir/obs.ws.sh"
. "$_osl_dir/obs.workspace-ff.sh"

# Default values
# ff means "folder-file"
obs_defaults_tabs_ff_name="Onglets Obsidian"
obs_defaults_tabs_ff_header="# Onglets Obsidian"
obs_defaults_tabs_ff_left_header="## Volet de gauche"
obs_defaults_tabs_ff_main_header="## Aire principale"

# Retrieve the list of the active 

# Create the tabs file if it does not exist.
obs.tabs_file.create(){
    vault_dir="${1:-$(obs.current_vault.path)}"

    # Use obs.workspace_ff.current() to retrieve the current workspace folder-file
    workspace_ff="$(obs.workspace_ff.current "$vault_dir")"
    
    # workspace_ff should exist
    if [ ! -d "$workspace_ff" ]; then
        printf 'Error: %s does not exist\n' "$workspace_ff"
        return 1
    fi
    tabs_ff="$workspace_ff/$obs_defaults_tabs_ff_name.md"
    if [ ! -f "$tabs_ff" ]; then
        printf '%s\n\n' "${obs_defaults_tabs_ff_header}" > "$tabs_ff"
    fi
}

# Update the tabs file with the current state of the workspace.
# If no vault path is given, use the current vault.
# Options:
#   --silent: do not print anything
# Arguments:
#   $1: vault path
# Return 1 if
#   - the current vault is not found;
#   - the workspace file is not found;
#   - the tabs file is not found.
obs.tabs_file.update(){
    silent=0
    if [ "$1" = "--silent" ]; then
        silent=1
        shift
    fi
    if ! vault_dir="${1:-$(obs.current_vault.path)}"; then
        printf 'Error: not a vault\n'
        return 1
    fi
    # Use obs.workspace_ff.current() to retrieve the current workspace folder-file
    workspace_ff_f="${vault_dir}/$(obs.workspace_ff.current "$vault_dir")"

    # workspace_ff should exist
    if [ -d "$workspace_ff_f" ]; then
        printf 'Error: no worskace file in the left pane\n'
        return 1
    fi

    # take the dirname of the workspace_ff using shell string manipulation
    workspace_ff_d="${workspace_ff_f%/*}"
    #log "workspace_ff_d: $workspace_ff_d"

    tabs_ff="$workspace_ff_d/$obs_defaults_tabs_ff_name.md"
    #log "tabs_ff: $tabs_ff"
    # tabs_ff should exist
    if [ ! -f "$tabs_ff" ]; then
        # Only print if not silent
        [ "$silent" -eq 0 ] && printf 'Error: %s does not exist\n' "$tabs_ff"
        return 1
    fi
    #log "tabs_ff: $tabs_ff"
    # Empty the file.
    echo > "$tabs_ff"
    {
        # Recreate the file and add the header
        printf '%s\n\n' "${obs_defaults_tabs_ff_header}"

        # Add the current vault's notes
        printf '%s\n\n' "${obs_defaults_tabs_ff_left_header}"
        obs.current_vault.notes_in_active_workspace "$vault_dir" "left" | obs.paths.as_links
        echo
        printf '%s\n\n' "${obs_defaults_tabs_ff_main_header}"
        obs.current_vault.notes_in_active_workspace "$vault_dir" "main" | obs.paths.as_links
    } >> "$tabs_ff"
}
