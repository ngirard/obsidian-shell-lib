#!/bin/bash

# Prevent from being sourced more than once
[ -n "${_OBS_WS_FIX_PATHS_SH:-}" ] && return || _OBS_WS_FIX_PATHS_SH=1

if [ -z "${_osl_dir}" ]; then
    # Define the library directory if not defined
    _osl_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
fi

# Dependencies
. "$_osl_dir/obs.core.sh"
. "$_osl_dir/obs.vaults.sh"

: <<'———'
# Rationale

Obsidian is a powerful note-taking and knowledge management application that allows users to create and organize their notes in workspaces. The workspaces are defined in the `.obsidian/workspaces.json` file, which contains a list of file paths to the notes in each workspace.

However, when a note is renamed, the change only propagates to the list of paths of the current workspace. The file paths in the other workspaces that reference the renamed note will no longer be valid. This can result in broken links within the notes and a disorganized vault.

This script is a temporary cure for this problem until it is fixed upstream. It checks the file paths in the workspaces.json file of an Obsidian vault and verifies if they still resolve to an existing Markdown file. In case a file path is no longer valid, it interactively offers a list of suitable matching existing file paths for replacement, sorted by decreasing Jaccard similarity.
———


# List the file paths of the given vault.
# We use 'fd' to list the files in the vault, but we exclude the '.obsidian' directory.
# The output of 'fd' is sorted.
# Arguments:
#  $1: vault path
# Return 1 if the vault path is not valid.
obs.vault.file_paths() {
    vault_dir="$1"
    if [ ! -d "$vault_dir" ]; then
        printf 'Error: not a vault\n' >&2
        return 1
    fi
    # Temporarily change the current directory to the vault directory
    # so that 'fd' can list the files in the vault
    pushd "$vault_dir" >/dev/null || return 1
    # List the files in the vault
    fd --no-ignore --type f --exclude '.obsidian' . | sort
    # Restore the current directory
    popd >/dev/null || return 1
}



: <<'———'
We will be using Ffs (the file filesystem) to expose the contents of the workspaces.json file as a filesystem. This will allow us to use the regular file system commands to manipulate the file paths in the workspaces.json file.

The paths we need to fix are all in the files named 'file' in the 'workspaces' directory of the mount point. Let's call them 'mounted attributes' for now.

Since we need to fix the paths in the workspaces.json file, i.e. the contents of the 'mounted attributes', we need to keep the path to the 'mounted attributes' as well as their contents in memory.

———

# Mount the given file as a filesystem using Ffs.
mount_file_as_fs() {
    file_path="$1"
    mountpoint="$2"
    mkdir -p "$mountpoint" || return 1
    # Mount the file as a filesystem
    ffs -i "$file_path" -m "$mountpoint" &
    sleep 1
}

# Unmount the given filesystem.
unmount_fs() {
    mountpoint="$1"
    # Unmount the filesystem
    fusermount3 -u "$mountpoint"
    # Remove the mountpoint
    rmdir "$mountpoint"
}

# Output the tabular-separated list of mounted attribute values in the given mount point
# Output format:
#  {mounted attribute value}
paths_in_mountpoint() {
    mountpoint="$1"
    # List the mounted attributes
    find "$mountpoint" -type f -name 'file'| while read -r file_path; do
        # Get the mounted attribute value
        value="$(cat "$file_path")"
        # Output the {mounted attribute value, mounted attribute path} pair
        printf '%s\n' "$value"
    done | sort
}




# Now, we need to filter out the paths that are no longer valid.
# Use comm for performance.
# Usage:
#  paths_in_mountpoint "$ffs_mountpoint" | filter_invalid_paths "$existing_paths_file"
filter_invalid_paths() {
    existing_paths_file="$1"
    comm -23 - "$existing_paths_file"
}


# filter_similar_paths - Filters a list of file paths based on their similarity to a given path
# 
# Usage:
#   echo "/path/to/file1.txt
#   /path/to/file2.txt
#   /path/to/file3.md" | filter_similar_paths "/path/to/file1.txt"
#
# Arguments:
# - path: The path to compare against (string).
# - format_string (optional): A string that specifies the format of the output. Default: '{path}'. Available placeholders: {path}, {basename}, {score}.
# - threshold (optional): The similarity threshold (float). Default: 0.6
#
# Input:
# The input is a list of file paths, one per line, from the standard input.
#
# Output:
# The output is a list of filtered file paths, sorted by descending similarity score, with each file path formatted according to the format string.
#
filter_similar_paths() {
  path="$1"
  format_string=${2:-'{path}'}
  threshold=${3:-0.6}
  python3 -c "
#!/usr/bin/env python3
import argparse
from math import exp
import sys
import os
from os.path import basename, splitext

def jaccard_similarity(x, y):
    x_set = set(x)
    y_set = set(y)
    intersection = x_set & y_set
    union = x_set | y_set
    return len(intersection) / len(union)


# Calculate the Levenshtein distance between two strings.
def levenshtein_distance(s1, s2):
    # Get the length of the two strings
    m = len(s1)
    n = len(s2)
    
    # Create a matrix to store the distances
    dp = [[0 for j in range(n + 1)] for i in range(m + 1)]
    
    # Initialize the first row and first column of the matrix
    for i in range(m + 1):
        dp[i][0] = i
    for j in range(n + 1):
        dp[0][j] = j
        
    # Iterate through the matrix and fill in the distances
    for i in range(1, m + 1):
        for j in range(1, n + 1):
            if s1[i - 1] == s2[j - 1]:
                dp[i][j] = dp[i - 1][j - 1]
            else:
                dp[i][j] = min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]) + 1
                
    # Return the distance stored in the bottom right corner of the matrix
    return dp[m][n]

# Calculate the Levenshtein similarity between two strings.
def levenshtein_similarity(x, y):
    return 1 - levenshtein_distance(x, y) / max(len(x), len(y))

def compare_paths(compare_path: str, format_string: str, threshold: float):
    sim_func = levenshtein_similarity
    #sim_func = jaccard_similarity
    # Get the basename and extension of the path to compare with (r = reference, c = candidate)
    r_path_without_ext, r_extension = splitext(compare_path)
    r_basename = basename(r_path_without_ext)

    # Read paths from standard input
    input_paths = (c_path.strip() for c_path in sys.stdin)
    # Filter paths with different extensions
    input_paths = ((c_path,) + splitext(c_path) for c_path in input_paths)
    input_paths = ((c_path, c_path_without_ext, basename(c_path_without_ext)) for c_path, c_path_without_ext, c_extension in input_paths
        if c_extension == r_extension)
    result = []

    for c_path, c_path_without_ext, c_path_basename in input_paths:
        # Provide a quick cutoff for paths that are obviously not similar using jaccard similarity which is much faster than levenshtein
        js = jaccard_similarity(r_path_without_ext, c_path_without_ext)
        if js < threshold:
            continue
        # Next, use levenshtein similarity to filter out the remaining paths
        bn_similarity:float = sim_func(r_basename, c_path_basename)
        if bn_similarity < threshold:
            continue
        path_similarity:float = sim_func(r_path_without_ext, c_path_without_ext)
        # Decay constant
        lmbda = 20
        # File was just moved
        mv = bn_similarity
        mv = exp(-lmbda*(1-mv))
        
        # File was just renamed
        ren = path_similarity
        ren = exp(-lmbda*(1-ren))
        
        c_score = mv + ren
        c_score = int(100*c_score)
        
        result.append((c_path, c_path_without_ext, c_path_basename, c_score))
    # sort the result by descending score
    result.sort(key=lambda x: x[3], reverse=True)
    # print the result
    for c_path, c_path_without_ext, c_path_basename, c_score in result:
        print(format_string.format(path=c_path, basename=c_path_basename, score=c_score))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('compare_path', help='Path to compare with')
    parser.add_argument('format_string', help='Format string for the output')
    parser.add_argument('threshold', help='Basename similarity threshold', type=float, default=0.6)
    args = parser.parse_args()
    
    # Call the comparison function
    compare_paths(args.compare_path, args.format_string, args.threshold)
" "$path" "$format_string" "$threshold"
}


# A function that displays a menu with options and returns the selected option.
# The options are read from the standard input and the prompt is provided as an argument.
# The function repeatedly displays the menu and waits for the user to enter a valid number
# between 0 and the number of options minus 1. If the user enters an invalid choice,
# an error message is displayed. The selected option is returned by the function.
#
# Example usage:
#   options=$(echo -e "option1\noption2\noption3")
#   selected_option=$(echo "$options" | display_menu "Choose an option")
#
display_menu(){
    prompt="$1"
    # Read the options from the standard input
    readarray -t options
    # The number of options
    num_options=${#options[@]}
    # Repeat until the user enters a valid choice
    while true; do
        # Display the options
        printf -- '--------------------------------\n' >&2
        for i in "${!options[@]}"; do
            printf '[%s] %s\n' "$i" "${options[i]}" >&2
        done
        # Display the prompt
        printf '%s (0-%s): ' "$prompt" "$((num_options - 1))" >&2
        # Read the user's choice
        read -r choice < /dev/tty
        # Check if the choice is valid
        if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 0 && choice < num_options)); then
            # The choice is valid
            # Return the selected option
            printf '%s' "${options[choice]}"
            return
        else
            # The choice is invalid
            # Display an error message
            printf 'Invalid choice. Please enter a number between 0 and %s.\n' "$((num_options - 1))" >&2
        fi
    done
}

# IMPORTANT: we systematically use printf instead of echo.

# This function takes a string as input and returns an escaped version of the string suitable for use as the replacement string in a sed command
escape_sed_replacement() {
  local replacement="$1"

  replacement="${replacement//\\/\\\\}"   # escape backslash characters
  replacement="${replacement//&/\\&}"     # escape ampersand characters
  replacement="${replacement//\//\\/}"    # escape forward slash characters
  replacement="${replacement//$'\n'/\\n}" # escape newline characters
  printf '%s' "$replacement"
}

# A function that reads a path from the standard input.
# The function presents the user with a list of up to 9 similar paths and allows them to either choose a path or leave the original string unchanged.
# The function returns 0 if the user chose a valid path, or 1 if the user chose to leave the original string unchanged.
# FIXME: For now, the function always returns 0.
# The selected option is printed to the standard output.
#
choose_valid_path(){
  paths_file="$1"
  # Read the path from the standard input
  read -r incorrect_path

  # Get the list of up to 9 similar paths to the incorrect path
  similar_paths="$(cat "$paths_file" | filter_similar_paths "$incorrect_path" '{path}' 0.6 | head -9)"

  # If there are no similar paths, return 1
  if [[ -z "$similar_paths" ]]; then
        log "No similar paths found for: $incorrect_path"
        return 1
  fi

  # Add the option to leave the original string unchanged
  printf -v options '%s\n%s' "$incorrect_path" "$similar_paths"

  # Present the list of options to the user and get their choice, using the display_menu function
  chosen_path="$(printf '%s' "$options" | display_menu 'Choose a path')"
  # Check if the user chose a valid path
  if [[ "$chosen_path" != "$incorrect_path" ]]; then
      # The user chose a valid path
      # print the pair of the original path and the chosen path as sed commands.
      # The chosen path is escaped using the escape_sed_replacement function.
      escaped_chosen_path="$(escape_sed_replacement "$chosen_path")"
      printf 's|%s|%s|g\n' "$incorrect_path" "${escaped_chosen_path}"
      return 0
  else
      # The user chose to leave the original string unchanged
      # Do nothing
      return 1
      #printf '%s\n' "$line"
      #return 1
  fi
}


paths_in_ws(){ ws_path="$1"; rg --only-matching '"file": "(.*\..*)",?$' -r '$1' "$ws_path" |sort|uniq; }

re(){ path="$1"; printf 'json.workspaces(?:\.|\[")(.*)(?:\.|"\])\.(?:main|left|right).*\.file = "%s";' "${path}"; }

# Function that prints the name of the workspaces that contain the given file path.
# Arguments:
#  $1: workspaces.json file path
#  $2: file path
# Example usage:
#   workspaces_containing_path workspaces.json "Path/to/file1.md"
#   returns:
#     Workspace 1
# Implementation detail:
#   Fuck jq. We'll be using gron (https://github.com/tomnomnom/gron) instead.
workspaces_containing_path(){
    ws_file="$1"
    path="$2"
    re='json.workspaces(?:\.|\[")(.*)(?:\.|"\])\.(?:main|left|right).*\.file = "(.*)";'
    gron "$ws_file" | rg --only-matching -r '$1|$2' "$re" | grep "|$path" | cut -d'|' -f1 | sort | uniq | tr '\n' '|' | sed 's/|$//'
}



maybe_display_missing_paths(){
    missing_paths_file="$1"
    # Store the number of missing paths
    num_missing_paths="$(wc -l < "$missing_paths_file")"
    log ""
    # Display the missing paths
    if ((num_missing_paths > 0)); then
        log "The following paths are missing from the vault:"
        cat "$missing_paths_file" |while read -r path; do
            printf -- '-----\nPath: %s\n' "$path"
            w="$(workspaces_containing_path ~/Obsidian/.obsidian/workspaces.json "$path")"
            printf 'Workspace(s): %s\n\n' "$w"; done
    else
        log "No missing paths found."
    fi
}



# Arguments:
#  $1: vault path
do_fix(){
    vault_dir="$1"
    # Create a temporary directory
    tmp_dir="$(mktemp -d)"
    log "Created temporary directory: $tmp_dir"
    existing_paths_file="$tmp_dir/existing_paths.txt"
    paths_in_ws_file="$tmp_dir/paths_in_ws.txt"
    invalid_paths_file="$tmp_dir/invalid_paths.txt"
    missing_paths_file="$tmp_dir/missing_paths.txt"
    ws_file="$vault_dir/.obsidian/workspaces.json"
    updated_ws_file="$tmp_dir/workspaces.updated.json"
    replacements_file="$tmp_dir/replacements.txt"
    
    # List the file paths of the vault
    log "Collecting existing paths data..."
    obs.vault.file_paths "$vault_dir" > "$existing_paths_file"

    log "Collecting the file paths of the workspaces.json file..."
    paths_in_ws "$vault_dir/.obsidian/workspaces.json" > "$paths_in_ws_file"

    log "Collecting the invalid file paths..."
    filter_invalid_paths "$existing_paths_file" < "$paths_in_ws_file" > "$invalid_paths_file"

    # Store the number of invalid paths
    num_invalid_paths="$(wc -l < "$invalid_paths_file")"

    # Exit if there are no invalid paths
    if ((num_invalid_paths == 0)); then
        log "There are no invalid paths. Exiting..."
        exit 0
    fi

    log "Found $num_invalid_paths invalid paths."


    # Ask the user to choose a valid path for each invalid path
    cat "$invalid_paths_file" | while read -r path; do
        if repl=$(choose_valid_path "$existing_paths_file" <<< "$path"); then
            printf '%s\n' "$repl" >> "$replacements_file"
        else
            printf '%s\n' "$path" >> "$missing_paths_file"
        fi
    done >> "$replacements_file"

    # Display the missing paths if there are any
    maybe_display_missing_paths "$missing_paths_file"

    # Update the workspaces.json file with the new paths
    log "Updating workspaces.json file with the new paths..."
    sed -f "$replacements_file" "$ws_file" > "$updated_ws_file"

    # Copy the updated workspaces.json file to the vault as workspaces.new.json
    new_file="${ws_file%.json}.new.json"
    log "Copying updated workspaces.json file to the vault as $new_file"
    cp "$updated_ws_file" "$new_file"

    # Display the shell command to rename the workspaces.new.json file to workspaces.json
    log "To rename the workspaces.new.json file to workspaces.json, execute the following command:"
    printf 'mv "%s" "%s"\n' "$new_file" "$vault_dir/.obsidian/workspaces.json"
}


# shellcheck disable=3028
if [ "$0" = "${BASH_SOURCE:-$0}" ]; then
  ####parse_arguments "$@"
  do_fix "$1"
fi