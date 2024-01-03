#!/bin/bash

# This is and old and unused version of the fix_obsidian_ws_paths.sh script.


# Prevent from being sourced more than once
[ -n "${_OBS_WS_FIX_PATHS_SH:-}" ] && return || _OBS_WS_FIX_PATHS_SH=1

# Define the library directory
lib_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# Dependencies
. "$lib_dir/obs.core.sh"
. "$lib_dir/obs.vaults.sh"

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

# Output the tabular-separated list of {mounted attribute path, mounted attribute value} pairs in the given mount point. The list is sorted by the mounted attribute path.
# Output format:
#  {mounted attribute value}\t{mounted attribute path}
paths_in_mountpoint() {
    mountpoint="$1"
    # List the mounted attributes
    find "$mountpoint" -type f -name 'file'| while read -r file_path; do
        # Get the mounted attribute value
        value="$(cat "$file_path")"
        # Output the {mounted attribute value, mounted attribute path} pair
        printf '%s\t%s\n' "$value" "$file_path"
    done | sort
}

# Now, since the paths can appear multiple times, we need to group the paths by their value. This will allow us to fix the paths in the workspaces.json file in a single pass.
# the "grouping" consists in joining the paths with the same value into a single line, separated by a '|' character.
# The input is assumed to be sorted by the value.
# Usage:
#  paths_in_mountpoint "$ffs_mountpoint" | group_by_value
# Input format:
#  {value1}\t{path1}
#  {value1}\t{path2}
#  {value2}\t{path3}
#  {value2}\t{path4}
# Output format:
#  {value1}\t{path1}|{path2}|...
#  {value2}\t{path3}|{path4}|...
grouped_by_value(){
    prev_value=""
    paths=""
    while read -r line; do
        value="${line%|*}"
        path="${line#*|}"
        if [ "$value" = "$prev_value" ]; then
            paths="$paths|$path"
        else
            if [ -n "$prev_value" ]; then
                printf "%s\t%s\n" "$prev_value" "$paths"
            fi
            prev_value="$value"
            paths="$path"
        fi
    done
    if [ -n "$prev_value" ]; then
        printf "%s\t%s\n" "$prev_value" "$paths"
    fi
}


# Now, we need to filter out the paths that are no longer valid.
# Usage:
#  paths_in_mountpoint "$ffs_mountpoint" | group_by_value | filter_invalid_paths "$existing_paths_file"
# Output format:
#  {value1}\t{path1}|{path2}|...
#  {value2}\t{path3}|{path4}|...    # This line is filtered out
filter_invalid_paths() {
    existing_paths_file="$1"
    # Filter out the paths that are no longer valid
    while read -r line; do
        # Get the value and the paths
        value="$(echo "$line" | awk -F '\t' '{print $1}')"
        # Check if the value is a valid path
        if ! grep -q "^$value\$" "$existing_paths_file"; then
            # The value is not a valid path
            # Output the line
            printf '%s\n' "$line"
        fi
    done
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
# - format_string (optional): A string that specifies the format of the output. Default: '{path}'
# - threshold (optional): The similarity threshold (float). Default: 0.7
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
  threshold=${3:-0.7}
  python3 -c "
import sys
import os

def jaccard_similarity(x, y):
    x_set = set(x)
    y_set = set(y)
    intersection = x_set & y_set
    union = x_set | y_set
    return len(intersection) / len(union)

def compare_paths(compare_path: str, threshold: float, format_string: str):
    # Get the basename and extension of the path to compare with
    base_name, extension = os.path.splitext(os.path.basename(compare_path))

    # Read paths from standard input
    input_paths = (path.strip() for path in sys.stdin)
    # Filter paths with different extensions
    input_paths = ((path,) + os.path.splitext(path) for path in input_paths)
    input_paths = ((path, path_basename) for path, path_basename, path_extension in input_paths 
        if path_extension == extension)
    result = []
    for path, path_basename in input_paths:
        similarity = jaccard_similarity(base_name, path_basename)
        if similarity >= threshold:
            result.append((path, path_basename, similarity))
    # sort the result by descending similarity
    result.sort(key=lambda x: x[2], reverse=True)
    # print the result
    for path, path_basename, similarity in result:
        print(format_string.format(path=path, basename=path_basename, similarity=similarity))

# Get the path to compare with and the format string and similarity threshold from command line arguments
compare_path = sys.argv[1]
format_string = sys.argv[2]
threshold = float(sys.argv[3])

# Call the comparison function
compare_paths(compare_path, threshold, format_string)
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

# A function that reads a line from the standard input in the format:
#   {incorrect path}\t{path1}|{path2}|...
# The function presents the user with a list of up to 9 similar paths and allows them to either choose a path or leave the original string unchanged.
# The function returns 0 if the user chose a valid path, or 1 if the user chose to leave the original string unchanged.
# FIXME: For now, the function always returns 0.
# The selected option is printed to the standard output in the format:
#   {chosen path}\t{path1}|{path2}|...
#
# Example usage:
#   paths_file="paths.txt"
#   line="incorrect/path/name	valid/path1|valid/path2|valid/path3"
#   selected_option=$(echo "$line" | choose_valid_path "$paths_file")
#   printf 'Selected option: %s\n' "$selected_option"
choose_valid_path(){
  paths_file="$1"
  # Read a line from the standard input
  read -r line

  # Get the incorrect path and the rest of the line
  IFS=$'\t' read -r incorrect_path rest_of_line <<< "$line"

  # Get the list of up to 9 similar paths to the incorrect path
  similar_paths="$(cat "$paths_file" | filter_similar_paths "$incorrect_path" '{path}' | head -9)"

  # Add the option to leave the original string unchanged
  printf -v options '%s\n%s' "$incorrect_path" "$similar_paths"

  # Present the list of options to the user and get their choice, using the display_menu function
  chosen_path="$(printf '%s' "$options" | display_menu 'Choose a path')"
  # Check if the user chose a valid path
  if [[ "$chosen_path" != "$incorrect_path" ]]; then
      # The user chose a valid path
      printf '%s\t%s\n' "$chosen_path" "$rest_of_line"
      return 0
  else
      # The user chose to leave the original string unchanged
      # Do nothing
      return 0
      #printf '%s\n' "$line"
      #return 1
  fi
}






# Then, we can write a function that takes the output produced by choose_valid_path and updates the "mounted arguments" file with the new path.
# Usage:
#  choose_valid_path "$paths_file" | update_workspaces_json
# Input format:
#  {chosen path}\t{path1}|{path2}|...
update_paths_in_mounted_arguments_file(){
    # Read a line from the standard input
    read -r line
    # Get the chosen path and the rest of the line
    chosen_path="$(echo "$line" | awk -F '\t' '{print $1}')"
    paths_to_update="$(echo "$line" | awk -F '\t' '{print $2}')" # This is a list of paths separated by the pipe character
    # Save the current IFS
    OLD_IFS="$IFS"
    # Set the IFS to the pipe character
    IFS='|'
    # For each path in the list of paths to update
    for path_to_update in $paths_to_update; do
        log "Updating path in mounted arguments file: $path_to_update"
        # check if the path exists
        if [ ! -f "$path_to_update" ]; then
            log "Path does not exist: $path_to_update"
            return 1
        fi
        # Update the path in the mounted arguments file
        echo "$chosen_path" > "$path_to_update" 
    done
    # Reset the IFS to its original value
    IFS="$OLD_IFS"
}

# Arguments:
#  $1: vault path
do_fix(){
    vault_dir="$1"
    # Create a temporary directory
    tmp_dir="$(mktemp -d)"
    log "Created temporary directory: $tmp_dir"
    ffs_mountpoint="$tmp_dir/ffs"
    existing_paths_file="$tmp_dir/existing_paths.txt"
    temp_ws_file="$tmp_dir/workspaces.json"
    
    # Copy the workspaces.json file to the temporary directory
    cp "$vault_dir/.obsidian/workspaces.json" "$temp_ws_file"
    
    # Mount the workspaces.json file as a filesystem
    log "Mounting workspaces.json file as a filesystem..."
    mount_file_as_fs "$temp_ws_file" "$ffs_mountpoint"

    # List the file paths of the vault
    log "Collecting existing paths data..."
    obs.vault.file_paths "$vault_dir" > "$existing_paths_file"

    # Collect the invalid paths data
    log "Collecting invalid paths data..."
    paths_in_mountpoint "$ffs_mountpoint" | grouped_by_value | filter_invalid_paths "$existing_paths_file" > "$tmp_dir/invalid_paths.txt"

    # Ask the user to choose a valid path for each invalid path
    log "Asking the user to choose a valid path for each invalid path..."
    cat "$tmp_dir/invalid_paths.txt" | while read -r line; do
        choose_valid_path "$existing_paths_file" <<< "$line"
    done >> "$tmp_dir/updated_invalid_paths.txt"

    # Update the workspaces.json file with the new paths
    log "Updating workspaces.json file with the new paths..."
    cat "$tmp_dir/updated_invalid_paths.txt" | update_paths_in_mounted_arguments_file

    # Unmount the filesystem
    log "Unmounting filesystem..."
    unmount_fs "$ffs_mountpoint"

    # Copy the updated workspaces.json file to the vault as workspaces.new.json
    new_file="$vault_dir/.obsidian/workspaces.new.json"
    log "Copying updated workspaces.json file to the vault as $new_file"
    cp "$temp_ws_file" "$new_file"

    # Rename the workspaces.json file to workspaces.old.json
    old_file="$vault_dir/.obsidian/workspaces.old.json"
    log "Renaming workspaces.json file to $old_file"
    mv "$vault_dir/.obsidian/workspaces.json" "$old_file"

    # Display the shell command to rename the workspaces.new.json file to workspaces.json
    log "To rename the workspaces.new.json file to workspaces.json, execute the following command:"
    printf 'mv "%s" "%s"\n' "$new_file" "$vault_dir/.obsidian/workspaces.json"
}


# shellcheck disable=3028
if [ "$0" = "${BASH_SOURCE:-$0}" ]; then
  ####parse_arguments "$@"
  do_fix "$1"
fi