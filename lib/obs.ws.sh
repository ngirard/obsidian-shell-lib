#!/bin/bash

# Prevent from being sourced more than once
[ -n "${_OBS_WS_SH:-}" ] && return || _OBS_WS_SH=1

# Define the library directory
_osl_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# Dependencies
. "$_osl_dir/obs.core.sh"
. "$_osl_dir/obs.vaults.sh"

# Return the path to the 'workspace.json' for the given vault path. If no vault path is given, use the current vault. Return 1 if the current vault is not found.
obs.vault.workspace_path(){
    vault_dir="${1:-$(obs.current_vault.path)}"
    if [ ! -d "$vault_dir" ]; then
        printf 'Error: not a vault\n' >&2
        return 1
    fi
    ws_path="$vault_dir/.obsidian/workspace.json"
    if [ ! -f "$ws_path" ]; then
        printf 'Error: no workspace file found\n' >&2
        return 1
    fi
    printf '%s' "$ws_path"
}

# Print the list of notes in the specified section of the active workspace as Obsidian links.
# When no vault path is given, use the current vault.
# The section argument is optional and defaults to 'main'.
# Possible values are 'main', 'left', 'right', and 'all'.
# In the latter case, all the links from the three sections are printed.
# Arguments:
#  $1: vault path (optional)
#  $2: section (optional)
# Return 1 if the current vault is not found.
obs.current_vault.notes_in_active_workspace() {
    defaultsection="main"
    section="$defaultsection"
    if [ "$#" -eq 2 ]; then
        ws_path="$(obs.vault.workspace_path "$1")"
        section="$2"
    elif [ "$#" -le 1 ]; then
        ws_path="$(obs.vault.workspace_path "${1:-$(obs.current_vault.path)}")"
    else
        printf 'Error: invalid number of arguments\n' >&2
        return 1
    fi

    jq_filter=".left.children[].children[]"
    case "$section" in
        left)
            ;;
        right)
            jq_filter=".right.children[].children[]"
            ;;
        all)
            jq_filter=".left.children[].children[], .main.children[].children[], .right.children[].children[]"
            ;;
        main)
            jq_filter=".main.children[].children[]"
            ;;
        *)
            printf 'Error: invalid section "%s"\n' "$section" >&2
            return 1
            ;;
    esac

    jq_filter="$jq_filter | select(.state?.state.file) | .state.state.file"
    jq -r "$jq_filter" "$ws_path"
}

# Return the path to the active file in the current vault.
obs.current_vault.active_file_id(){
    vault_dir="${1:-$(obs.current_vault.path)}"
    ws_path="$vault_dir/.obsidian/workspace.json"
    # Get the id of the active file
    id=$(jq -r '.active' "$ws_path")
    # Return the path of the file with this id
    jq -r --arg id "$id" '.main.children[].children[] | select(.id == $id) | .state.state.file' "$ws_path"
}
