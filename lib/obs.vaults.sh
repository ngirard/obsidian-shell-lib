#!/bin/bash

# Prevent from being sourced more than once
[ -n "${_OBS_VAULTS_SH:-}" ] && return || _OBS_VAULTS_SH=1

# Define the library directory
_osl_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# Dependencies
. "$_osl_dir/obs.core.sh"


: <<'———'
Example of obsidian.json:
{
    "vaults": {
        "89da3d6a85cc0210": { // Open vault
            "path": "/home/u/Obsidian",
            "ts": 1675788239937, // <--- timestamp
            "open": true
        },
        "a9da3d6a85cc0210": { // Closed vault
            "path": "/home/u/Obsidian2",
            "ts": 1675788239937
        }
    },
    "lastActiveVault": "89da3d6a85cc0210"
}
———



# Extract the list of vault paths from the obsidian.json file.
# Arguments:
#   state (optional): the state of the vaults to return. Possible values are 'open', 'closed', and 'all'. Defaults to 'all'.
# Return the value of the 'path' field of each vault in the obsidian.json file that matches the given state.
obs.vaults.paths(){
    state="${1:-all}"
    case "$state" in
        open)
            jq -r '.vaults | to_entries[] | select(.value.open == true) | .value.path' "$(obs.config.file)"
            ;;
        closed)
            jq -r '.vaults | to_entries[] | select(.value.open != true) | .value.path' "$(obs.config.file)"
            ;;
        all)
            jq -r '.vaults | to_entries[] | .value.path' "$(obs.config.file)"
            ;;
        *)
            printf 'Error: invalid state: %s\n' "$state" >&2
            return 1
            ;;
    esac
}

# Return the path to the most recently opened vault, i.e. the vault whose 'ts' field is the highest among the open vaults.
obs.vaults.last_active.path(){
    jq -r '.vaults | to_entries[] | select(.value.open == true) | .value.path' "$(obs.config.file)" | sort -r | head -n 1
}


# Use jq to get the id of the vault whose path is given as an argument.
obs.vaults.id(){
    path="$1"
    jq -r --arg path "$path" '.vaults | to_entries[] | select(.value.path == $path) | .key' "$(obs.config.path)"
}

# Look for a .obsidian directory in the current directory or any of its parents and return the absolute path to it.
obs.current_vault.path(){
    dir="$PWD"
    if [ -z "$dir" ]; then
        printf 'Error: PWD is empty\n' >&2
        return 1
    fi
    while [ "$dir" != '/' ]; do
        if [ -d "$dir/.obsidian" ]; then
            printf '%s' "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
        # FIXME: dir="${dir%/*}"
    done
    return 1
}
