#!/bin/bash

# Prevent from being sourced more than once
[ -n "${_OBS_CORE_SH:-}" ] && return || _OBS_CORE_SH=1

# Logs to stderr
log(){
    printf '%s\n' "$*" >&2
}

# Return the name of the current platform.
# Possible values are 'linux', 'macos', 'windows'.
obs.platform(){
    case "$OSTYPE" in
        linux*)
            printf '%s' "linux"
            ;;
        darwin*)
            printf '%s' "macos"
            ;;
        msys*)
            printf '%s' "windows"
            ;;
        *)
            printf 'Error: unknown platform\n' >&2
            return 1
            ;;
    esac
}

# Return the path to the Obsidian configuration directory.
# The configuration directory is the directory where Obsidian stores its configuration files.
# On Linux, it is ~/.config/obsidian.
# On macOS, it is ~/Library/Application Support/obsidian.
# On Windows, it is %APPDATA%\obsidian.
obs.config.dir(){
    case "$(obs.platform)" in
        linux)
            printf '%s' "$HOME/.config/obsidian"
            ;;
        macos)
            printf '%s' "$HOME/Library/Application Support/obsidian"
            ;;
        windows)
            printf '%s' "$APPDATA/obsidian"
            ;;
        *)
            printf 'Error: unknown platform\n' >&2
            return 1
            ;;
    esac
}

# Return the path to the Obsidian configuration file <config_dir>/obsidian.json
# The configuration file is the file where Obsidian stores its configuration about the vaults.
obs.config.file(){
    printf '%s' "$(obs.config.dir)/obsidian.json"
}

# Return the link name of the given path.
obs.link_name(){
    path="$1";
    printf '%s' "${path##*/}";
}

# Read a list of note paths and print them as Obsidian links.
obs.paths.as_links(){
    while read -r path; do
        # Remove the .md extension
        path="${path%.*}";
        printf '[[%s|%s]]\n' "$path" "$(obs.link_name "$path")" 
    done
}

# Filter the input lines as paths to keep only the ones that match the given basename.
obs.paths.only_matching_basename(){
    while read -r line; do
        if [ "${line##*/}" = "$1" ]; then
            printf '%s\n' "$line"
        fi
    done
}

# is_obsidian_running: Check if Obsidian is running
#
# Usage:
#   if is_obsidian_running; then
#     echo "Obsidian is running"
#   else
#     echo "Obsidian is not running"
#   fi
is_obsidian_running() {
    # shellcheck disable=SC2009
    ps aux | grep -E -q -i '[oO]bsidian.+type=gpu-process.+user-data-dir'
}